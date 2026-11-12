# logdiff <run>/logs/runtime-oldbase.log -> <run>/logs/runtime-newafter.log

start window: old 71 lines (started: True), new 98 lines (started: True); after-startup lines old 5, new 6; other new INFO signatures outside after-startup: 31
FAIL 0 | REVIEW 0 | PASS* 4 | INFO 0

PASS*  NEW              INFO LoggingModule: Initializing Logging module prefilter.
                        after-startup line not in the old log (accepted: new line from Logging 2.3.0 (planned module update), informational)
PASS*  NEW_WARNING      WARNING Configuration: Using derived value for ClusterManagerActionInterval (# ms) based on SessionTimeout, as the default would exceed the maximum of # * session timeout.
                        (accepted: test harness: runapp.py starts with SessionTimeout 30000 ms, Mendix 10 derives this interval from it; production sets its own)
PASS*  NEW_WARNING      WARNING Configuration: Using derived value for SessionKeepAliveUpdatesInterval (# ms) based on ClusterManagerActionInterval, as the default would exceed the maximum of half of the ClusterManagerActionInterval or exceed SessionTimeout.
                        (accepted: test harness: runapp.py starts every app with SessionTimeout 30000 ms, so the runtime derives the keep-alive interval; production sets its own)
PASS*  NEW_WARNING      WARNING LicenseService: The runtime has been started using a trial license, the framework will be terminated when the maximum time is exceeded!
                        (accepted: test harness: local runtime without a license key; Mendix 10 words the trial warning differently from 9)
