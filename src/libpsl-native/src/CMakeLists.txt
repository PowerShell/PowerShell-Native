include(CheckIncludeFiles)
include(CheckFunctionExists)

add_library(psl-native SHARED
  getstat.cpp
  getlstat.cpp
  getcommonstat.cpp
  getcommonlstat.cpp
  getpwuid.cpp
  getgrgid.cpp
  getppid.cpp
  getuserfrompid.cpp
  getfileowner.cpp
  getcurrentthreadid.cpp
  getcurrentprocessorid.cpp
  getcomputername.cpp
  getlinkcount.cpp
  geterrorcategory.cpp
  getinodedata.cpp
  isfile.cpp
  isdirectory.cpp
  issamefilesystemitem.cpp
  issymlink.cpp
  isexecutable.cpp
  setdate.cpp
  createhardlink.cpp
  createsymlink.cpp
  followsymlink.cpp
  createprocess.cpp
  nativesyslog.cpp)

check_function_exists(sysconf HAVE_SYSCONF)

check_include_files(
    "sys/sysctl.h"
    HAVE_SYS_SYSCTL_H)

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/pal_config.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/pal_config.h)

target_include_directories(psl-native PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
