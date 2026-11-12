# Java class clashes

```
CLASH 338 classes in 17 packages (org.apache.commons.lang3, org.apache.commons.lang3.arch, org.apache.commons.lang3.builder, ...)
  userlib/commons-lang3-3.11.jar [commons-lang3 3.11; modules: DeepLink,CommunityCommons]
  userlib/commons-lang3-3.12.0.jar [commons-lang3 3.12.0; modules: MendixSSO]
  same artifact org.apache.commons:commons-lang3 (3.11 vs 3.12.0) under two file names: jardedupe.py groups these
CLASH 182 classes in 10 packages (org.apache.commons.io, org.apache.commons.io.comparator, org.apache.commons.io.file, ...)
  userlib/commons-io-2.11.0.jar [commons-io 2.11.0; modules: CommunityCommons,Encryption]
  userlib/commons-io-2.8.0.jar [commons-io 2.8.0; modules: DeepLink,CommunityCommons]
  same artifact commons-io:commons-io (2.11.0 vs 2.8.0) under two file names: jardedupe.py groups these
CLASH 22 classes in 2 packages (com.google.errorprone.annotations, com.google.errorprone.annotations.concurrent)
  userlib/error_prone_annotations-2.5.1.jar [error_prone_annotations 2.5.1; modules: CommunityCommons]
  userlib/error_prone_annotations-2.7.1.jar [error_prone_annotations 2.7.1; modules: CommunityCommons]
  same artifact com.google.errorprone:error_prone_annotations (2.5.1 vs 2.7.1) under two file names: jardedupe.py groups these
```
