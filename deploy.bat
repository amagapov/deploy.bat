@echo off
chcp 65001>nul

:: считываем параметр запуска скрипта и проверяем его
set param=%1
set first=%param:~,1%

if "%param%"=="" (
  echo Необходим параметр - название тестовой площадки
  echo Пример: deploy /alpha1
  goto :ENDOFSCRIPT
) else (
if not "%first%"=="/" (
  echo Параметр задан неверно
  echo Пример: deploy /alpha1
  goto :ENDOFSCRIPT
))

set param=%param:/=%

set res=false
if "%param%"=="alpha1" set res=true
if "%param%"=="develop" set res=true
if "%res%"=="false" (
  echo Параметр задан неверно
  echo Допустимые значения параметров: alpha1, develop
  goto :ENDOFSCRIPT
)

:: получаем дату и время для имени папки сборки
time /t>.tmp
for /F %%i in (.tmp) do set timeVar=%%i
date /t>.tmp
for /F %%i in (.tmp) do set dateVar=%%i
set dateTime=%dateVar:.=%_%timeVar::=%
del .tmp

::======================================= переменные путей (редактировать только здесь) =======================================
:: testArea - название тестовой ветки
set testArea=%param%

:: buildDir - название папки, в которой будут храниться собранные бинарники и лог
set buildDir=C:\user.home\builds\%testArea%\%dateTime%\

:: serv - строка доступа к серверу тестовых площадок
set serv=SFTP://root:...:888

:: srvFolder - общая папка на сервере тестовой площадки
set srvFolder=/home/...

:: projDir - папка исходников, где лежит файл проекта 1C-Connect.groupproj
set projDir=C:\git\

:: необходимые утилиты, если путь к ним не прописан в системной PATH, то указать абсолютный путь (если в пути есть пробел, не забыть кавычки)
set SQLiteExe=sqlite3.exe
set SQLiteDif=sqldiff.exe
set msbuildExe=%systemroot%\microsoft.net\framework\v3.5\MSBuild.exe
set eurecaExe="C:\Program Files (x86)\EurekaLab\EurekaLog 7\Packages\Delphi19\ecc32.exe"
set upxExe="C:\Program Files (x86)\Ultimate Packer\upx.exe"
set wmic=%SystemRoot%\System32\wbem\wmic.exe
set inoSetup="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

:: переменные путей для сборки инсталлятора
set SetupFileName=1C-ConnectSetup
set Ico=C:\git\ResImages\icons\task.ico
set BinariesDir=C:\user.home\builds\installer\agentBinaries
set SourceDir=C:\user.home\builds\installer\sourceFiles
set inoSetupScript=C:\user.home\builds\installer\script.iss

:: переменные для сборки локалей
set createDBScript=%projDir%Local\createLng.sql
set localDir=%projDir:\=/%Local/
set localRus=%localDir%dbRus/
set localUkr=%localDir%dbUkr/
set localEng=%localDir%dbEng/

:: общие переменные
set rusDBName=Russian.lng
set ukrDBName=Ukraine.lng
set engDBName=English.lng
set exeName=1C-Connect.exe
set updIniName=updates_%testArea%.htm
set exeSect=[Agent4]
set rusSect=[Localization_Russian]
set ukrSect=[Localization_Ukraine]
set engSect=[Localization_English]
set md5Key=MD5
set minVerKey=MinimalVersion
set verKey=Version
::=============================================================================================================================

:: переменные, не требующие ручной правки
set logFileName=%buildDir%%dateTime%.log
set emptyString=
set md5Empty=noDif
set lngRus=%buildDir%%rusDBName%
set lngUkr=%buildDir%%ukrDBName%
set lngEng=%buildDir%%engDBName%
set tablesListSQL=SELECT name FROM sqlite_master WHERE type = 'table';
set ProdName=%exeName:.exe=%
set SourceExe=%SourceDir%\%exeName%

::=============================================================================================================================
::===================================================== НАЧАЛО ПРОГРАММЫ ======================================================

:: создание папок для сборки
md %buildDir%old

:: формирование и запуск скрипта для WinSCP для скачивания файлов с тестовой площадки
echo 1)  Скачивание файлов с тестовой площадки %testArea% ...
echo option batch abort>winSCPget.tmp
echo option confirm off>>winSCPget.tmp
echo open %serv%>>winSCPget.tmp
echo get %srvFolder%%updIniName% %buildDir%old\>>winSCPget.tmp
echo get %srvFolder%%testArea%/%exeName% %buildDir%old\>>winSCPget.tmp
echo get %srvFolder%%testArea%/Data/%rusDBName% %buildDir%old\>>winSCPget.tmp
echo get %srvFolder%%testArea%/Data/%ukrDBName% %buildDir%old\>>winSCPget.tmp
echo get %srvFolder%%testArea%/Data/%engDBName% %buildDir%old\>>winSCPget.tmp
echo close>>winSCPget.tmp
echo exit>>winSCPget.tmp
start /wait WinSCP.exe /console /script=winSCPget.tmp

echo Files from distribs.buhphone.com received>>%logFileName% 2>&1
echo 2)  Файлы с %testArea% получены ...

:: получение версии "старого" экзешника, скачанного с тестовой площадки, и переименовывание 1C-Connect.exe -> версия.exe для отправки обратно на тестовую площадку
for /f "tokens=2 delims==" %%i in ('%wmic% DATAFILE WHERE name^="%buildDir:\=\\%old\\%exeName%" get Version /VALUE 2^>nul') do set "exeOldVersion=%%i"
copy /y %buildDir%old\%exeName% %buildDir%%exeOldVersion%.exe>>nul
echo Exe copied to %buildDir%%exeOldVersion%.exe>>%logFileName% 2>&1
echo 3)  Скачанный файл %exeName% переименован в %exeOldVersion%.exe ...

:: сборка нового экзешника, получение его md5 и версии
echo 4)  Сборка нового исполняемого файла %exeName% ...
call :BUILDEXE
echo Exe builded>>%logFileName% 2>&1
copy /y %projDir%Build\Pr_Agent4.exe %buildDir%%exeName%>>nul
echo Exe copied to %buildDir%%exeName%>>%logFileName% 2>&1
call :GETMD5 %exeName%
set md5Exe=%Result%
for /f "tokens=2 delims==" %%i in ('%wmic% DATAFILE WHERE name^="%buildDir:\=\\%%exeName%" get Version /VALUE 2^>nul') do set exeNewVersion=%%i
echo %exeName% md5sum: %md5Exe%, version: %exeNewVersion%>>%logFileName% 2>&1
echo 5)  Собран новый исполняемый файл %exeName% md5sum: %md5Exe%, version: %exeNewVersion% ...

:: сборк бинарников локалей, получение их md5
call :BUILDLNG

call :GETMD5 %rusDBName%
set md5Rus=%Result%
echo %rusDBName% md5sum = %md5Rus%>>%logFileName% 2>&1
echo 6)  Собран новый файл локализации %rusDBName% md5sum: %md5Rus% ...

call :GETMD5 %ukrDBName%
set md5Ukr=%Result%
echo %ukrDBName% md5sum = %md5Ukr%>>%logFileName% 2>&1
echo 7)  Собран новый файл локализации %ukrDBName% md5sum: %md5Ukr% ...

call :GETMD5 %engDBName%
set md5Eng=%Result%
echo %engDBName% md5sum = %md5Eng%>>%logFileName% 2>&1
echo 8)  Собран новый файл локализации %engDBName% md5sum: %md5Eng% ...

:: формирование нового updates.htm
SETLOCAL ENABLEDELAYEDEXPANSION
for /F "tokens=1,2* delims==" %%i in (%buildDir%old\%updIniName%) do (
	if "%%j"=="%emptyString%" (
		set section=%%i
		if not "!section!"=="%exeSect%" (echo.>>%buildDir%%updIniName%)
		echo %%i>>%buildDir%%updIniName%
	) else (
		if "!section!"=="%exeSect%" (
			if "%%i"=="%verKey%" (echo %%i=%exeNewVersion%>>%buildDir%%updIniName%) else (
			if "%%i"=="%minVerKey%" (echo %%i=%exeNewVersion%>>%buildDir%%updIniName%) else (
			if "%%i"=="%md5Key%" (echo %%i=%md5Exe%>>%buildDir%%updIniName%) else (echo %%i=%%j>>%buildDir%%updIniName%)))
		) else (
		if "!section!"=="%rusSect%" (
			if "%%i"=="%verKey%" (if "%md5Rus%"=="%md5Empty%" (echo %%i=%%j>>%buildDir%%updIniName%) else (echo %%i=%md5Rus%>>%buildDir%%updIniName%)) else (echo %%i=%%j>>%buildDir%%updIniName%)
		) else (
		if "!section!"=="%ukrSect%" (
			if "%%i"=="%verKey%" (if "%md5Ukr%"=="%md5Empty%" (echo %%i=%%j>>%buildDir%%updIniName%) else (echo %%i=%md5Ukr%>>%buildDir%%updIniName%)) else (echo %%i=%%j>>%buildDir%%updIniName%)
		) else (
		if "!section!"=="%engSect%" (
			if "%%i"=="%verKey%" (if "%md5Eng%"=="%md5Empty%" (echo %%i=%%j>>%buildDir%%updIniName%) else (echo %%i=%md5Eng%>>%buildDir%%updIniName%)) else (echo %%i=%%j>>%buildDir%%updIniName%)
		) else (echo %%i=%%j>>%buildDir%%updIniName%))))
	)
)
SETLOCAL DISABLEDELAYEDEXPANSION
echo Created %updIniName%>>%logFileName% 2>&1
echo 9)  Сформирован updates_%testArea%.htm ...

:: формирование и запуск скрипта для WinSCP для отправки файлов на тестовую площадку
echo 10) Отправка файлов на тестовую площадку %testArea% ...
echo option batch abort>winSCPput.tmp
echo option confirm off>>winSCPput.tmp
echo open %serv%>>winSCPput.tmp
echo put %buildDir%%updIniName% %srvFolder%>>winSCPput.tmp
echo File for send %buildDir%%updIniName%>>%logFileName% 2>&1

echo put %buildDir%%exeName% %srvFolder%%testArea%/>>winSCPput.tmp
echo File for send %buildDir%%exeName%>>%logFileName% 2>&1

echo put %buildDir%%exeOldVersion%.exe %srvFolder%%testArea%/>>winSCPput.tmp
echo File for send %buildDir%%exeOldVersion%.exe>>%logFileName% 2>&1

if NOT "%md5Rus%"=="%md5Empty%" (
  echo put %buildDir%%rusDBName% %srvFolder%%testArea%/Data/>>winSCPput.tmp
  echo File for send %buildDir%%rusDBName%>>%logFileName% 2>&1
)
if NOT "%md5Ukr%"=="%md5Empty%" (
  echo put %buildDir%%ukrDBName% %srvFolder%%testArea%/Data/>>winSCPput.tmp
  echo File for send %buildDir%%ukrDBName%>>%logFileName% 2>&1
)
if NOT "%md5Eng%"=="%md5Empty%" (
  echo put %buildDir%%engDBName% %srvFolder%%testArea%/Data/>>winSCPput.tmp
  echo File for send %buildDir%%engDBName%>>%logFileName% 2>&1
)
echo close>>winSCPput.tmp
echo exit>>winSCPput.tmp
start /wait WinSCP.exe /console /script=winSCPput.tmp
echo Files sent to %srvFolder%>>%logFileName% 2>&1
echo >>%logFileName% 2>&1

del *.tmp
:: rd /s /q %buildDir%old
echo 11) Файлы на %testArea% отправлены ...
echo 12) Сборка инсталлятора ...

call :BUILDINSTALLER

echo 13) Инсталлятор собран ...
echo 14) Работа скрипта завершена.

::====================================================== КОНЕЦ ПРОГРАММЫ ======================================================
::=============================================================================================================================


::======================================================== подсчет md5 ========================================================
goto :ENDOFSCRIPT
:GETMD5
set _md5=%md5Empty%
set file=%1
echo %file% checksum calculation>>%logFileName% 2>&1
if "%file%"=="%exeName%" (
  echo any text>.tmp
) else (
  %SQLiteDif% %buildDir%old\%file% %buildDir%%file%>.tmp
)
if exist md5.tmp del md5.tmp
for /f %%i in (.tmp) do (
  Certutil -hashfile %buildDir%%file% MD5>md5.tmp
  for /f "skip=1 tokens=*" %%k in (md5.tmp) do (
    set _md5=%%k
    goto BREAKCYCLE
  )
)
:BREAKCYCLE
set Result=%_md5: =%
exit /b
::=============================================================================================================================

::====================================================== сборка экзешника =====================================================
:BUILDEXE
:: сборка
call rsvars.bat
%msbuildExe% /t:Clean %projDir%Pr_Agent4.dproj>>%logFileName% 2>&1
%msbuildExe% /t:Build /p:Config=Debug %projDir%Pr_Agent4.dproj>>%logFileName% 2>&1

:: включение EurecaLog
%eurecaExe% "--el_alter_exe=%projDir%Pr_Agent4.dproj;%projDir%Build\Pr_Agent4.exe" "--el_outputfilename=%projDir%Build\Pr_Agent4.exe" --el_nostats>>%logFileName% 2>&1

:: сжатие
%upxExe% --lzma --best %projDir%Build\Pr_Agent4.exe>>%logFileName% 2>&1

:: удаление временных файлов и переименование агента
del /s /q %projDir%Build\*.drc %projDir%Build\*.map %projDir%Build\*.tds>>%logFileName% 2>&1
exit /b
::=============================================================================================================================

::====================================================== сборка локалей =======================================================
:BUILDLNG
:: создаем базу данных 
%SQLiteExe% "%lngRus%"<"%createDBScript%"
%SQLiteExe% "%lngUkr%"<"%createDBScript%"
%SQLiteExe% "%lngEng%"<"%createDBScript%"
echo Created new databases %lngRus%, %lngUkr%, %lngEng%>>%logFileName% 2>&1

:: получаем список таблиц
%SQLiteExe% "%lngRus%" "%tablesListSQL%">tableList.tmp

:: формируем скрипт для импорта данных в базу и выполняем его (русская локализация)
echo .mode csv>.tmp
echo .separator "|">>.tmp
for /F %%i in (tableList.tmp) do echo .import '%localRus%%%i.csv' %%i>>.tmp
echo .quit>>.tmp
%SQLiteExe% "%lngRus%"<.tmp
echo Builded and filled %lngRus%>>%logFileName% 2>&1

:: формируем скрипт для импорта данных в базу и выполняем его (украинская локализация)
echo .mode csv>.tmp
echo .separator "|">>.tmp
for /F %%i in (tableList.tmp) do echo .import '%localUkr%%%i.csv' %%i>>.tmp
echo .quit>>.tmp
%SQLiteExe% "%lngUkr%"<.tmp
echo Builded and filled %lngUkr%>>%logFileName% 2>&1

:: формируем скрипт для импорта данных в базу и выполняем его (английская локализация)
echo .mode csv>.tmp
echo .separator "|">>.tmp
for /F %%i in (tableList.tmp) do echo .import '%localEng%%%i.csv' %%i>>.tmp
echo .quit>>.tmp
%SQLiteExe% "%lngEng%"<.tmp
echo Builded and filled %lngEng%>>%logFileName% 2>&1

exit /b
::=============================================================================================================================

::======================================================== подсчет md5 ========================================================
goto :ENDOFSCRIPT
:BUILDINSTALLER
echo #define ProductName "%ProdName%">"%inoSetupScript%"
echo #define Ver "%exeNewVersion%">>"%inoSetupScript%"
echo #define ExeName "%exeName%">>"%inoSetupScript%"
echo #define DirOfSetupFile "%buildDir%">>"%inoSetupScript%"
echo #define NameOfSetupFile "%SetupFileName%">>"%inoSetupScript%"
echo #define IconPath "%Ico%">>"%inoSetupScript%"
echo #define SrcDir "%SourceDir%\*">>"%inoSetupScript%"
echo #define SrcExe "%SourceExe%">>"%inoSetupScript%"

echo [Setup]>>"%inoSetupScript%"
echo AppName={#ProductName}>>"%inoSetupScript%"
echo AppVersion={#Ver}>>"%inoSetupScript%"
echo AppPublisher={#ProductName}>>"%inoSetupScript%"
echo CreateUninstallRegKey=no>>"%inoSetupScript%"
echo Compression=lzma>>"%inoSetupScript%"
echo DefaultDirName={%%USERPROFILE}\{#ProductName}>>"%inoSetupScript%"
echo DisableProgramGroupPage=yes>>"%inoSetupScript%"
echo OutputDir={#DirOfSetupFile}>>"%inoSetupScript%"
echo OutputBaseFileName={#NameOfSetupFile}>>"%inoSetupScript%"
echo PrivilegesRequired=lowest>>"%inoSetupScript%"
echo SetupIconFile={#IconPath}>>"%inoSetupScript%"
echo SolidCompression=yes>>"%inoSetupScript%"
echo Uninstallable=no>>"%inoSetupScript%"
echo VersionInfoVersion={#Ver}>>"%inoSetupScript%"

echo [Languages]>>"%inoSetupScript%"
echo Name: "en"; MessagesFile: "compiler:Default.isl">>"%inoSetupScript%"
echo Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl">>"%inoSetupScript%"
echo Name: "ukr"; MessagesFile: "compiler:Languages\Ukrainian.isl">>"%inoSetupScript%"

echo [Tasks]>>"%inoSetupScript%"
echo Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked>>"%inoSetupScript%"

echo [Files]>>"%inoSetupScript%"
echo Source: {#SrcDir}; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs>>"%inoSetupScript%"
echo Source: {#SrcExe}; DestDir: "{app}"; Flags: ignoreversion>>"%inoSetupScript%"

echo [Icons]>>"%inoSetupScript%"
echo Name: "{userdesktop}\{#ProductName}"; Filename: "{app}\{#ExeName}"; IconFileName: "{app}\{#ExeName}"; Tasks: desktopicon>>"%inoSetupScript%"

xcopy %BinariesDir% %SourceDir% /e /y /r>>nul
copy /y %buildDir%%rusDBName% %SourceDir%\Data\%rusDBName%>>nul
copy /y %buildDir%%ukrDBName% %SourceDir%\Data\%ukrDBName%>>nul
copy /y %buildDir%%engDBName% %SourceDir%\Data\%engDBName%>>nul
copy /y %buildDir%%exeName% %SourceDir%>>nul

%inoSetup% "%inoSetupScript%">>%logFileName% 2>&1

exit /b
::=============================================================================================================================

:ENDOFSCRIPT