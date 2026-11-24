@echo off
rem FujiBarrage for the NABU PC: runs tools\nabu\build.py (its top lists the
rem options: set SERVER=host:port, TEST_SCENE, DEBUG, LOCAL_DIR).
rem   build-nabu.bat          r2r\nabu\barrage.nabu (and a copy in c:\nabu\local)
rem   build-nabu.bat clean
if "%PYTHON%"=="" set PYTHON=python
%PYTHON% "%~dp0tools\nabu\build.py" %*
