# Java class clashes

```
CLASH 3228 classes in 125 packages (org.bouncycastle, org.bouncycastle.asn1, org.bouncycastle.asn1.anssi, ...)
  userlib/bcprov-jdk15on-1.69.jar [manifest org.bouncycastle.provider 1.69; modules: Encryption]
  vendorlib/bcprov-jdk18on-1.81.jar [manifest bcprov 1.81; modules: -]
  same artifact org.bouncycastle.provider (1.69 vs 1.81) under two file names: jardedupe.py groups these
CLASH 1937 classes in 18 packages (com.google.common.annotations, com.google.common.base, com.google.common.base.internal, ...)
  userlib/guava-30.1.1-jre.jar [guava 30.1.1-jre; modules: CommunityCommons]
  vendorlib/guava-32.0.1-jre.jar [guava 32.0.1-jre; modules: -]
  same artifact com.google.guava:guava (30.1.1-jre vs 32.0.1-jre) under two file names: jardedupe.py groups these
CLASH 1894 classes in 18 packages (com.google.common.annotations, com.google.common.base, com.google.common.base.internal, ...)
  vendorlib/guava-32.0.1-jre.jar [guava 32.0.1-jre; modules: -]
  vendorlib/guava-33.5.0-jre.jar [guava 33.5.0-jre; modules: -]
  same artifact com.google.guava:guava (32.0.1-jre vs 33.5.0-jre) under two file names: jardedupe.py groups these
CLASH 1849 classes in 18 packages (com.google.common.annotations, com.google.common.base, com.google.common.base.internal, ...)
  userlib/guava-30.1.1-jre.jar [guava 30.1.1-jre; modules: CommunityCommons]
  vendorlib/guava-33.5.0-jre.jar [guava 33.5.0-jre; modules: -]
  same artifact com.google.guava:guava (30.1.1-jre vs 33.5.0-jre) under two file names: jardedupe.py groups these
CLASH 752 classes in 46 packages (org.bouncycastle.cert, org.bouncycastle.cert.bc, org.bouncycastle.cert.cmp, ...)
  userlib/bcpkix-jdk15on-1.69.jar [manifest org.bouncycastle.pkix 1.69; modules: Encryption]
  vendorlib/bcpkix-jdk18on-1.81.jar [manifest bcpkix 1.81; modules: -]
  same artifact org.bouncycastle.pkix (1.69 vs 1.81) under two file names: jardedupe.py groups these
CLASH 736 classes in 23 packages (com.fasterxml.jackson.databind, com.fasterxml.jackson.databind.annotation, com.fasterxml.jackson.databind.cfg, ...)
  userlib/jackson-databind-2.14.1.jar [jackson-databind 2.14.1; modules: -]
  vendorlib/jackson-databind-2.20.1.jar [jackson-databind 2.20.1; modules: -]
  same artifact com.fasterxml.jackson.core:jackson-databind (2.14.1 vs 2.20.1) under two file names: jardedupe.py groups these
CLASH 715 classes in 53 packages (org.apache.pdfbox.contentstream, org.apache.pdfbox.contentstream.operator, org.apache.pdfbox.contentstream.operator.color, ...)
  userlib/pdfbox-2.0.24.jar [pdfbox 2.0.24; modules: CommunityCommons]
  vendorlib/pdfbox-3.0.7.jar [pdfbox 3.0.7; modules: -]
  same artifact org.apache.pdfbox:pdfbox (2.0.24 vs 3.0.7) under two file names: jardedupe.py groups these
CLASH 395 classes in 18 packages (org.apache.commons.lang3, org.apache.commons.lang3.arch, org.apache.commons.lang3.builder, ...)
  vendorlib/commons-lang3-3.18.0.jar [commons-lang3 3.18.0; modules: -]
  vendorlib/commons-lang3-3.20.0.jar [commons-lang3 3.20.0; modules: -]
  same artifact org.apache.commons:commons-lang3 (3.18.0 vs 3.20.0) under two file names: jardedupe.py groups these
CLASH 338 classes in 17 packages (org.apache.commons.lang3, org.apache.commons.lang3.arch, org.apache.commons.lang3.builder, ...)
  userlib/commons-lang3-3.11.jar [commons-lang3 3.11; modules: DeepLink,CommunityCommons]
  userlib/commons-lang3-3.12.0.jar [commons-lang3 3.12.0; modules: MendixSSO]
  same artifact org.apache.commons:commons-lang3 (3.11 vs 3.12.0) under two file names: jardedupe.py groups these
CLASH 335 classes in 15 packages (org.apache.commons.io, org.apache.commons.io.build, org.apache.commons.io.channels, ...)
  vendorlib/commons-io-2.17.0.jar [commons-io 2.17.0; modules: -]
  vendorlib/commons-io-2.21.0.jar [commons-io 2.21.0; modules: -]
  same artifact commons-io:commons-io (2.17.0 vs 2.21.0) under two file names: jardedupe.py groups these
CLASH 329 classes in 29 packages (org.checkerframework.checker.builder.qual, org.checkerframework.checker.calledmethods.qual, org.checkerframework.checker.compilermsgs.qual, ...)
  userlib/checker-qual-3.8.0.jar [manifest org.checkerframework.checker.qual 3.8.0; modules: CommunityCommons]
  vendorlib/checker-qual-3.33.0.jar [manifest org.checkerframework.checker.qual 3.33.0; modules: -]
  same artifact org.checkerframework.checker.qual (3.8.0 vs 3.33.0) under two file names: jardedupe.py groups these
CLASH 323 classes in 17 packages (org.apache.commons.lang3, org.apache.commons.lang3.arch, org.apache.commons.lang3.builder, ...)
  userlib/commons-lang3-3.12.0.jar [commons-lang3 3.12.0; modules: MendixSSO]
  vendorlib/commons-lang3-3.18.0.jar [commons-lang3 3.18.0; modules: -]
  same artifact org.apache.commons:commons-lang3 (3.12.0 vs 3.18.0) under two file names: jardedupe.py groups these
CLASH 323 classes in 17 packages (org.apache.commons.lang3, org.apache.commons.lang3.arch, org.apache.commons.lang3.builder, ...)
  userlib/commons-lang3-3.12.0.jar [commons-lang3 3.12.0; modules: MendixSSO]
  vendorlib/commons-lang3-3.20.0.jar [commons-lang3 3.20.0; modules: -]
  same artifact org.apache.commons:commons-lang3 (3.12.0 vs 3.20.0) under two file names: jardedupe.py groups these
CLASH 317 classes in 17 packages (org.apache.commons.lang3, org.apache.commons.lang3.arch, org.apache.commons.lang3.builder, ...)
  userlib/commons-lang3-3.11.jar [commons-lang3 3.11; modules: DeepLink,CommunityCommons]
  vendorlib/commons-lang3-3.18.0.jar [commons-lang3 3.18.0; modules: -]
  same artifact org.apache.commons:commons-lang3 (3.11 vs 3.18.0) under two file names: jardedupe.py groups these
CLASH 317 classes in 17 packages (org.apache.commons.lang3, org.apache.commons.lang3.arch, org.apache.commons.lang3.builder, ...)
  userlib/commons-lang3-3.11.jar [commons-lang3 3.11; modules: DeepLink,CommunityCommons]
  vendorlib/commons-lang3-3.20.0.jar [commons-lang3 3.20.0; modules: -]
  same artifact org.apache.commons:commons-lang3 (3.11 vs 3.20.0) under two file names: jardedupe.py groups these
CLASH 258 classes in 17 packages (org.bouncycastle.asn1.bsi, org.bouncycastle.asn1.cmc, org.bouncycastle.asn1.cmp, ...)
  userlib/bcutil-jdk15on-1.69.jar [manifest org.bouncycastle.util 1.69; modules: Encryption]
  vendorlib/bcutil-jdk18on-1.81.jar [manifest bcutil 1.81; modules: -]
  same artifact org.bouncycastle.util (1.69 vs 1.81) under two file names: jardedupe.py groups these
CLASH 201 classes in 11 packages (org.apache.commons.io, org.apache.commons.io.comparator, org.apache.commons.io.file, ...)
  userlib/commons-io-2.11.0.jar [commons-io 2.11.0; modules: CommunityCommons,Encryption]
  vendorlib/commons-io-2.17.0.jar [commons-io 2.17.0; modules: -]
  same artifact commons-io:commons-io (2.11.0 vs 2.17.0) under two file names: jardedupe.py groups these
CLASH 201 classes in 11 packages (org.apache.commons.io, org.apache.commons.io.comparator, org.apache.commons.io.file, ...)
  userlib/commons-io-2.11.0.jar [commons-io 2.11.0; modules: CommunityCommons,Encryption]
  vendorlib/commons-io-2.21.0.jar [commons-io 2.21.0; modules: -]
  same artifact commons-io:commons-io (2.11.0 vs 2.21.0) under two file names: jardedupe.py groups these
CLASH 182 classes in 10 packages (org.apache.commons.io, org.apache.commons.io.comparator, org.apache.commons.io.file, ...)
  userlib/commons-io-2.11.0.jar [commons-io 2.11.0; modules: CommunityCommons,Encryption]
  userlib/commons-io-2.8.0.jar [commons-io 2.8.0; modules: DeepLink,CommunityCommons]
  same artifact commons-io:commons-io (2.11.0 vs 2.8.0) under two file names: jardedupe.py groups these
CLASH 182 classes in 10 packages (org.apache.commons.io, org.apache.commons.io.comparator, org.apache.commons.io.file, ...)
  userlib/commons-io-2.8.0.jar [commons-io 2.8.0; modules: DeepLink,CommunityCommons]
  vendorlib/commons-io-2.17.0.jar [commons-io 2.17.0; modules: -]
  same artifact commons-io:commons-io (2.8.0 vs 2.17.0) under two file names: jardedupe.py groups these
CLASH 182 classes in 10 packages (org.apache.commons.io, org.apache.commons.io.comparator, org.apache.commons.io.file, ...)
  userlib/commons-io-2.8.0.jar [commons-io 2.8.0; modules: DeepLink,CommunityCommons]
  vendorlib/commons-io-2.21.0.jar [commons-io 2.21.0; modules: -]
  same artifact commons-io:commons-io (2.8.0 vs 2.21.0) under two file names: jardedupe.py groups these
CLASH 146 classes in 8 packages (org.apache.commons.text, org.apache.commons.text.diff, org.apache.commons.text.io, ...)
  userlib/commons-text-1.10.0.jar [commons-text 1.10.0; modules: MendixSSO,DeepLink]
  vendorlib/commons-text-1.10.0.jar [commons-text 1.10.0; modules: -]
  same artifact org.apache.commons:commons-text (1.10.0 vs 1.10.0) under two file names: jardedupe.py groups these
CLASH 145 classes in 8 packages (org.apache.commons.text, org.apache.commons.text.diff, org.apache.commons.text.io, ...)
  userlib/commons-text-1.10.0.jar [commons-text 1.10.0; modules: MendixSSO,DeepLink]
  vendorlib/commons-text-1.14.0.jar [commons-text 1.14.0; modules: -]
  same artifact org.apache.commons:commons-text (1.10.0 vs 1.14.0) under two file names: jardedupe.py groups these
CLASH 145 classes in 8 packages (org.apache.commons.text, org.apache.commons.text.diff, org.apache.commons.text.io, ...)
  vendorlib/commons-text-1.10.0.jar [commons-text 1.10.0; modules: -]
  vendorlib/commons-text-1.14.0.jar [commons-text 1.14.0; modules: -]
  same artifact org.apache.commons:commons-text (1.10.0 vs 1.14.0) under two file names: jardedupe.py groups these
CLASH 135 classes in 13 packages (com.fasterxml.jackson.core, com.fasterxml.jackson.core.async, com.fasterxml.jackson.core.base, ...)
  userlib/jackson-core-2.14.1.jar [jackson-core 2.14.1; modules: -]
  vendorlib/jackson-core-2.20.1.jar [jackson-core 2.20.1; modules: -]
  same artifact com.fasterxml.jackson.core:jackson-core (2.14.1 vs 2.20.1) under two file names: jardedupe.py groups these
CLASH 131 classes in 10 packages (org.apache.fontbox, org.apache.fontbox.afm, org.apache.fontbox.cff, ...)
  userlib/fontbox-2.0.24.jar [fontbox 2.0.24; modules: CommunityCommons]
  vendorlib/fontbox-3.0.7.jar [fontbox 3.0.7; modules: -]
  same artifact org.apache.pdfbox:fontbox (2.0.24 vs 3.0.7) under two file names: jardedupe.py groups these
CLASH 113 classes in 2 packages (org.owasp.html, org.owasp.html.examples)
  userlib/owasp-java-html-sanitizer-20211018.2.jar [owasp-java-html-sanitizer 20211018.2; modules: CommunityCommons]
  vendorlib/owasp-java-html-sanitizer-20260101.1.jar [owasp-java-html-sanitizer 20260101.1; modules: -]
  same artifact com.googlecode.owasp-java-html-sanitizer:owasp-java-html-sanitizer (20211018.2 vs 20260101.1) under two file names: jardedupe.py groups these
CLASH 71 classes in 1 packages (com.fasterxml.jackson.annotation)
  userlib/jackson-annotations-2.14.1.jar [jackson-annotations 2.14.1; modules: -]
  vendorlib/jackson-annotations-2.20.jar [jackson-annotations 2.20; modules: -]
  same artifact com.fasterxml.jackson.core:jackson-annotations (2.14.1 vs 2.20) under two file names: jardedupe.py groups these
CLASH 49 classes in 5 packages (com.auth0.jwt, com.auth0.jwt.algorithms, com.auth0.jwt.exceptions, ...)
  userlib/java-jwt-3.8.3.jar [no maven metadata; modules: JWT]
  vendorlib/java-jwt-3.19.4.jar [no maven metadata; modules: -]
  same artifact java-jwt (3.8.3 vs 3.19.4) under two file names: jardedupe.py groups these
CLASH 35 classes in 3 packages (javax.annotation, javax.annotation.concurrent, javax.annotation.meta)
  userlib/jsr305-3.0.2.jar [jsr305 3.0.2; modules: CommunityCommons]
  vendorlib/jsr305-3.0.2.jar [jsr305 3.0.2; modules: -]
  same artifact com.google.code.findbugs:jsr305 (3.0.2 vs 3.0.2) under two file names: jardedupe.py groups these
CLASH 26 classes in 2 packages (com.google.errorprone.annotations, com.google.errorprone.annotations.concurrent)
  vendorlib/error_prone_annotations-2.18.0.jar [error_prone_annotations 2.18.0; modules: -]
  vendorlib/error_prone_annotations-2.41.0.jar [error_prone_annotations 2.41.0; modules: -]
  same artifact com.google.errorprone:error_prone_annotations (2.18.0 vs 2.41.0) under two file names: jardedupe.py groups these
CLASH 24 classes in 2 packages (com.google.errorprone.annotations, com.google.errorprone.annotations.concurrent)
  userlib/error_prone_annotations-2.7.1.jar [error_prone_annotations 2.7.1; modules: CommunityCommons]
  vendorlib/error_prone_annotations-2.18.0.jar [error_prone_annotations 2.18.0; modules: -]
  same artifact com.google.errorprone:error_prone_annotations (2.7.1 vs 2.18.0) under two file names: jardedupe.py groups these
CLASH 24 classes in 2 packages (com.google.errorprone.annotations, com.google.errorprone.annotations.concurrent)
  userlib/error_prone_annotations-2.7.1.jar [error_prone_annotations 2.7.1; modules: CommunityCommons]
  vendorlib/error_prone_annotations-2.41.0.jar [error_prone_annotations 2.41.0; modules: -]
  same artifact com.google.errorprone:error_prone_annotations (2.7.1 vs 2.41.0) under two file names: jardedupe.py groups these
CLASH 22 classes in 14 packages (org.bouncycastle.asn1.cryptlib, org.bouncycastle.asn1.edec, org.bouncycastle.asn1.gnu, ...)
  userlib/bcprov-jdk15on-1.69.jar [manifest org.bouncycastle.provider 1.69; modules: Encryption]
  vendorlib/bcutil-jdk18on-1.81.jar [manifest bcutil 1.81; modules: -]
CLASH 22 classes in 2 packages (com.google.errorprone.annotations, com.google.errorprone.annotations.concurrent)
  userlib/error_prone_annotations-2.5.1.jar [error_prone_annotations 2.5.1; modules: CommunityCommons]
  userlib/error_prone_annotations-2.7.1.jar [error_prone_annotations 2.7.1; modules: CommunityCommons]
  same artifact com.google.errorprone:error_prone_annotations (2.5.1 vs 2.7.1) under two file names: jardedupe.py groups these
CLASH 22 classes in 2 packages (com.google.errorprone.annotations, com.google.errorprone.annotations.concurrent)
  userlib/error_prone_annotations-2.5.1.jar [error_prone_annotations 2.5.1; modules: CommunityCommons]
  vendorlib/error_prone_annotations-2.18.0.jar [error_prone_annotations 2.18.0; modules: -]
  same artifact com.google.errorprone:error_prone_annotations (2.5.1 vs 2.18.0) under two file names: jardedupe.py groups these
CLASH 22 classes in 2 packages (com.google.errorprone.annotations, com.google.errorprone.annotations.concurrent)
  userlib/error_prone_annotations-2.5.1.jar [error_prone_annotations 2.5.1; modules: CommunityCommons]
  vendorlib/error_prone_annotations-2.41.0.jar [error_prone_annotations 2.41.0; modules: -]
  same artifact com.google.errorprone:error_prone_annotations (2.5.1 vs 2.41.0) under two file names: jardedupe.py groups these
CLASH 18 classes in 2 packages (org.apache.commons.logging, org.apache.commons.logging.impl)
  userlib/commons-logging-1.2.jar [commons-logging 1.2; modules: CommunityCommons]
  vendorlib/commons-logging-1.3.5.jar [commons-logging 1.3.5; modules: -]
  same artifact commons-logging:commons-logging (1.2 vs 1.3.5) under two file names: jardedupe.py groups these
CLASH 13 classes in 1 packages (com.google.j2objc.annotations)
  vendorlib/j2objc-annotations-2.8.jar [j2objc-annotations 2.8; modules: -]
  vendorlib/j2objc-annotations-3.1.jar [j2objc-annotations 3.1; modules: -]
  same artifact com.google.j2objc:j2objc-annotations (2.8 vs 3.1) under two file names: jardedupe.py groups these
CLASH 12 classes in 1 packages (com.google.j2objc.annotations)
  userlib/j2objc-annotations-1.3.jar [j2objc-annotations 1.3; modules: CommunityCommons]
  vendorlib/j2objc-annotations-2.8.jar [j2objc-annotations 2.8; modules: -]
  same artifact com.google.j2objc:j2objc-annotations (1.3 vs 2.8) under two file names: jardedupe.py groups these
CLASH 12 classes in 1 packages (com.google.j2objc.annotations)
  userlib/j2objc-annotations-1.3.jar [j2objc-annotations 1.3; modules: CommunityCommons]
  vendorlib/j2objc-annotations-3.1.jar [j2objc-annotations 3.1; modules: -]
  same artifact com.google.j2objc:j2objc-annotations (1.3 vs 3.1) under two file names: jardedupe.py groups these
CLASH 9 classes in 1 packages (org.apache.pdfbox.io)
  userlib/pdfbox-2.0.24.jar [pdfbox 2.0.24; modules: CommunityCommons]
  vendorlib/pdfbox-io-3.0.7.jar [pdfbox-io 3.0.7; modules: -]
```
