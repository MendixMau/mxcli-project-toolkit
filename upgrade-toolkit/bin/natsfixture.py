#!/usr/bin/env python3
"""natsfixture.py: a local NATS broker for the test setup, the same for the old and the new app (steps/heal.md, NATS broker).

Why: an app with the Mendix NATS connector shows a "NATS server connection error" dialog on every page that connects, on
the old app and the new one. With no broker the journeys that open those dialogs fail on both sides and can only be
classed BASELINE DEFECT. This starts a throwaway broker and writes the test values the connector needs. Nothing is read
from or sent to a customer system; every secret here is generated locally and lives only under <work>/natsfixture.

What the connector needs (read from its Java action ConnectToNatsServer and its connect microflow):
  - TLS: a JKS key store and trust store named keystore.jks and truststore.jks in the constant NATS_CertificateStorePath.
    The trust store password opens both files (loadKeystore), the key store password is the key password.
  - an NKey seed (ConnectionData.UserNkeyPrivateKey): the broker admits that public key; a second seed in
    ConnectionData.IssuerPrivateKey (the home page event starts the auth callout service, which decodes it).
  - a host and port on ConnectionData (default row), no redundancy URLs (the client shuffles servers).
  - constants NATS_CertificateStorePath, NATS_CertificateAlgorithm, NATS_AUTHCalloutAccount (non empty).
The broker runs as container <prefix>-nats (prefix: UPG_NAME, default mig) on the runapp network mig-net, image nats:2
(official, arm64 on this Mac). Reached from the app containers as <prefix>-nats:4222; the work folder is mounted at /w there.

  natsfixture.py up   --work W [--prefix P]   generate the files once, start the broker, write W/natsfixture/overrides.json
  natsfixture.py seed --work W --psql 'docker exec -i mig-pg psql -U mendix -d DB' [--prefix P]
                                              point the default ConnectionData rows at the broker (same call for old and new)
  natsfixture.py down --work W [--prefix P]   stop and remove the container (files stay)
  natsfixture.py check --work W [--prefix P]  exit 0 when the broker log says it is ready
  natsfixture.py spki  --work W               print the base64 SHA-256 of the broker certificate's public key (see browser stage)
Browser stage (a test-only stand-in, not the real broker and not the real identity provider):
  - the connector's browser client dials wss://<WebsocketHostName>:<WebSocketPort> with the signed in user's IdP access token.
    The broker gets a second listener (websocket, TLS, container port 8443, published on 127.0.0.1:<ws-port>, default 18443).
  - stand-in auth: the websocket listener maps a client that sends no token to a test user (no_auth_user), so the journeys
    reach the "connected" state without an IdP. A real token is never validated here. Report it as: "stand-in broker and
    auth; real broker and IdP to be checked at deploy".
  - stand-in token (UPG_NATS_WS_TOKEN=<value>): when the test users carry a stored sign-in token (work/test-setup-users.sql), the
    browser client sends it, and a broker with NKey users rejects a token ("Authentification error" dialog). With the variable
    set, `up` starts a second container <prefix>-natsws that owns the websocket listener and accepts exactly that one token; the
    main broker (NKey, the Java connector) then has no websocket listener. Still a stand-in: nothing validates a real token.
  - trust: the test browser trusts exactly this certificate, for nothing else: export UPG_BROWSER_SPKI=$(natsfixture.py spki ...);
    vendor/e2e/helpers.js passes it to Chromium as --ignore-certificate-errors-spki-list.
Exit: 0 ok, 1 failed, 2 usage.
"""
import argparse, json, os, shlex, shutil, subprocess, sys, tempfile
from pathlib import Path

NET = "mig-net"
IMAGE = "nats:2"
PWD = "natstest-only"           # one password for the trust store, key store and key: generated for the fixture, not a secret
ALGORITHM = "SunX509"            # valid for KeyManagerFactory and TrustManagerFactory
WS_PORT = 18443                  # host port of the websocket listener (127.0.0.1 only)
ACCOUNT = "TEST"                 # the connector only passes it on to the auth callout service, which the fixture does not run

NKEY_JAVA = """import io.nats.client.NKey;
import java.security.SecureRandom;
public class NKeyGen { public static void main(String[] a) throws Exception {
  NKey k = NKey.createUser(new SecureRandom());
  System.out.println(new String(k.getSeed())); System.out.println(new String(k.getPublicKey()));
  NKey i = NKey.createAccount(new SecureRandom());   // the connector's auth callout service signs with this seed (IssuerPrivateKey)
  System.out.println(new String(i.getSeed())); } }
"""


def sh(*cmd, check=True, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if check and r.returncode != 0:
        sys.exit(f"natsfixture: command failed ({r.returncode}): {' '.join(cmd[:4])}...\n{r.stdout[-400:]}{r.stderr[-400:]}")
    return r


def find_jnats():
    """The app's userlib folder (jnats and its eddsa jar): the same NKey code the connector uses. Returns a java classpath."""
    for root in (os.environ.get("APP", ""), os.environ.get("UPG_ROOT", "") + "/app", str(Path.cwd() / "app")):
        for j in sorted(Path(root).glob("userlib/jnats-2*.jar")) if root else []:
            if "json" not in j.name:
                return str(j.parent / "*")
    sys.exit("natsfixture: no userlib/jnats-2*.jar found (set APP to the app folder)")


def gen(fx, host):
    certs = fx / "certs"
    if (certs / "keystore.jks").exists() and (fx / "nkey.json").exists():
        return
    certs.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix="natsfx-"))
    try:
        ks, ts, p12 = certs / "keystore.jks", certs / "truststore.jks", tmp / "server.p12"
        for f in (ks, ts):
            f.unlink(missing_ok=True)
        # server identity: self-signed, SAN for the container name and localhost; the trust store holds exactly that cert
        srv = tmp / "server.jks"
        sh("keytool", "-genkeypair", "-alias", "natsserver", "-keyalg", "RSA", "-keysize", "2048", "-validity", "3650",
           "-dname", "CN=nats-test", "-ext", "SAN=dns:NATSHOST,dns:localhost,ip:127.0.0.1".replace("NATSHOST", host),
           "-keystore", str(srv), "-storepass", PWD, "-keypass", PWD, "-storetype", "JKS")
        cer = tmp / "server.cer"
        sh("keytool", "-exportcert", "-alias", "natsserver", "-keystore", str(srv), "-storepass", PWD, "-file", str(cer))
        sh("keytool", "-importcert", "-noprompt", "-alias", "natsserver", "-file", str(cer), "-keystore", str(ts),
           "-storepass", PWD, "-storetype", "JKS")
        # the connector also loads a key store (client identity); the broker does not ask for it
        sh("keytool", "-genkeypair", "-alias", "client", "-keyalg", "RSA", "-keysize", "2048", "-validity", "3650",
           "-dname", "CN=nats-test-client", "-keystore", str(ks), "-storepass", PWD, "-keypass", PWD, "-storetype", "JKS")
        sh("keytool", "-importkeystore", "-srckeystore", str(srv), "-srcstorepass", PWD, "-destkeystore", str(p12),
           "-deststoretype", "PKCS12", "-deststorepass", PWD, "-destkeypass", PWD, "-srcalias", "natsserver")
        sh("openssl", "pkcs12", "-in", str(p12), "-passin", f"pass:{PWD}", "-nodes", "-nokeys", "-out", str(fx / "server-cert.pem"))
        sh("openssl", "pkcs12", "-in", str(p12), "-passin", f"pass:{PWD}", "-nodes", "-nocerts", "-out", str(fx / "server-key.pem"))
        # an NKey user, with the app's own jnats jar (the seed is what the connector signs the broker's nonce with)
        (tmp / "NKeyGen.java").write_text(NKEY_JAVA)
        out = sh("java", "-cp", find_jnats(), str(tmp / "NKeyGen.java")).stdout.split()
        seed, pub, iseed = out[-3], out[-2], out[-1]
        (fx / "nkey.json").write_text(json.dumps({"seed": seed, "public": pub, "issuer_seed": iseed}))
        for f in (fx / "server-key.pem", fx / "nkey.json"):
            f.chmod(0o644)  # the broker's user in the container must read the key; the folder is local and throwaway
        (fx / "overrides.json").write_text(json.dumps({
            "NatsConnector.NATS_CertificateStorePath": "/w/natsfixture/certs",
            "NatsConnector.NATS_CertificateAlgorithm": ALGORITHM,
            "NatsConnector.NATS_AUTHCalloutAccount": ACCOUNT}, indent=1))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def write_conf(fx, ws_token=""):
    """The broker config, rewritten on every `up` (cheap, so an older fixture folder gains the websocket listener).
    With ws_token the websocket listener moves to a second broker (conf_ws) that accepts only that token (a broker with NKey
    users cannot also check a token)."""
    pub = json.loads((fx / "nkey.json").read_text())["public"]
    tls = '  tls {\n    cert_file: "/etc/nats-test/server-cert.pem"\n    key_file: "/etc/nats-test/server-key.pem"\n  }\n'
    ws_own = 'websocket {\n  port: 8443\n  no_auth_user: "browser"\n' + tls + '}\n'
    (fx / "nats-server.conf").write_text(
        'debug: true\nport: 4222\ntls {\n  cert_file: "/etc/nats-test/server-cert.pem"\n  key_file: "/etc/nats-test/server-key.pem"\n  timeout: 5\n}\n'
        'authorization {\n  users = [ { nkey: %s }, { user: "browser", password: "%s" } ]\n}\n' % (pub, PWD)
        + ("" if ws_token else ws_own))
    if ws_token:
        (fx / "nats-ws.conf").write_text('debug: true\nport: 4223\nauthorization {\n  token: "%s"\n}\nwebsocket {\n  port: 8443\n%s}\n' % (ws_token, tls))


def spki(fx):
    """base64(sha256(DER public key)) of the broker certificate: the value Chromium's --ignore-certificate-errors-spki-list takes."""
    pk = subprocess.run(["openssl", "x509", "-in", str(fx / "server-cert.pem"), "-pubkey", "-noout"], capture_output=True, text=True)
    der = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=pk.stdout.encode(), capture_output=True)
    dg = subprocess.run(["openssl", "dgst", "-sha256", "-binary"], input=der.stdout, capture_output=True)
    import base64
    if pk.returncode or not dg.stdout:
        sys.exit("natsfixture: could not compute the certificate key hash")
    return base64.b64encode(dg.stdout).decode()


def cname(prefix):
    return f"{prefix}-nats"


def up(a):
    fx = Path(a.work) / "natsfixture"
    fx.mkdir(parents=True, exist_ok=True)
    gen(fx, cname(a.prefix))
    tok = os.environ.get("UPG_NATS_WS_TOKEN", "")
    write_conf(fx, tok)
    c = cname(a.prefix)
    sh("docker", "network", "create", NET, check=False)
    sh("docker", "rm", "-f", c, c + "ws", check=False)   # only our own container names
    pub = [] if tok else ["-p", f"127.0.0.1:{a.ws_port}:8443"]
    sh("docker", "run", "-d", "--name", c, "--network", NET, *pub, "-v", f"{fx}:/etc/nats-test:ro",
       IMAGE, "-c", "/etc/nats-test/nats-server.conf")
    if tok:
        sh("docker", "run", "-d", "--name", c + "ws", "--network", NET, "-p", f"127.0.0.1:{a.ws_port}:8443", "-v", f"{fx}:/etc/nats-test:ro",
           IMAGE, "-c", "/etc/nats-test/nats-ws.conf")
    print(f"natsfixture: {c} started ({IMAGE}); constants in {fx}/overrides.json; app sees nats://{c}:4222, browser wss://localhost:{a.ws_port}")


def down(a):
    sh("docker", "rm", "-f", cname(a.prefix), cname(a.prefix) + "ws", check=False)
    print(f"natsfixture: {cname(a.prefix)} removed")


def check(a):
    r = sh("docker", "logs", cname(a.prefix), check=False)
    if "Server is ready" not in r.stdout + r.stderr:
        sys.exit("natsfixture: broker not ready:\n" + (r.stdout + r.stderr)[-300:])
    print("natsfixture: broker ready")


def seed(a):
    fx = Path(a.work) / "natsfixture"
    k = json.loads((fx / "nkey.json").read_text())
    sql = ("update \"natsconnector$connectiondata\" set natshostname='%s', port=4222, usernkeyprivatekey='%s', "
           "issuerprivatekey='%s', truststorepwd='%s', keystorepwd='%s', redundancynatsserverurls='', "
           "websockethostname='localhost', websocketport=%d, redundancywebsocketurls='' where isdefault;"
           % (cname(a.prefix), k["seed"], k["issuer_seed"], PWD, PWD, a.ws_port))
    r = subprocess.run(shlex.split(a.psql) + ["-v", "ON_ERROR_STOP=1", "-c", sql], capture_output=True, text=True)
    if r.returncode != 0 or "UPDATE 0" in r.stdout:
        sys.exit(f"natsfixture: seed failed: {r.stdout}{r.stderr}")
    print("natsfixture: seeded " + r.stdout.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["up", "down", "seed", "check", "spki"])
    ap.add_argument("--work", required=True)
    ap.add_argument("--prefix", default=os.environ.get("UPG_NATS_NAME") or os.environ.get("UPG_NAME", "mig"))   # UPG_NATS_NAME: reuse another run's broker
    ap.add_argument("--psql")
    ap.add_argument("--ws-port", type=int, default=int(os.environ.get("UPG_NATS_WS_PORT", WS_PORT)))
    a = ap.parse_args()
    if a.cmd == "seed" and not a.psql:
        sys.exit(2)
    if a.cmd == "spki":
        print(spki(Path(a.work) / "natsfixture"))
        return
    {"up": up, "down": down, "seed": seed, "check": check}[a.cmd](a)


if __name__ == "__main__":
    main()
