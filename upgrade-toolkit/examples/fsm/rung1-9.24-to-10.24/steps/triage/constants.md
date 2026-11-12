# constcheck <run>/old-9.24.2.6130.mda -> <run>/new-10.24.28.129343.mda

constants old 47, new 48; configuration old -, new -; environment overrides 0
FAIL 0 | REVIEW 0 | PASS* 1 | INFO 2 | PASS 46

PASS*  ADDED    Logging.EnablePreFilter  default 'True'; behaviour switch, the app runs with 'True' (accepted: Logging 2.3.0 default True turns on the log prefilter (drops noisy framework lines before they reach log nodes); app does not depend on those lines and no app logic reads the switch, so keep the module default)
INFO   ADDED    Logging.CleanupFilter  default ''
INFO   REMOVED  NanoflowCommons.Nanoflow_Commons_Version  was '2.1.0'
