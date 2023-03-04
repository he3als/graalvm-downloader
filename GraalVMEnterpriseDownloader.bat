<# : batch portion
@echo off & cls
if "%~1"=="folderPick" goto folderPick
title GraalVM Enterprise Downloader Script ^| he3als

:: Set first digit of Win version (determines if it is 7+)
for /f "tokens=4 delims=. " %%a in ('ver') do (set winVersion=%%a)

:: Check if user is on Win Vista or below
:: Why are you running this on Vista or below...
if %winVersion% LSS 6 (
	echo Your Windows version is not supported.
	ver
	pause
	exit /b 1
)

:: Check if the user is on Win 7/8
:: If so, warn them that they need the latest PowerShell
if "%winVersion%"=="6" (
	echo WARNING: It seems like you are on Windows 7 or 8.
	echo          Make sure that you have the latest PowerShell update installed.
	echo          Otherwise, this script will completely break.
	echo]
	echo LINK: https://www.microsoft.com/en-us/download/details.aspx?id=54616
	timeout /nobreak 2 > nul
	pause
)

:: Check for 32-bit
if "%PROCESSOR_ARCHITECTURE%"=="x86" (
	echo GraalVM is not supported on 32-bit Windows/computers.
	pause
	exit /b 1
)

echo Which GraalVM EE version do you want to download?
echo]
echo [1] Java 17
echo [2] Java 11
echo [3] Java 8
echo]
choice /c:123 /n /m "Enter your selection [1/2/3]: "
if %errorlevel%==1 set javaVersion=17
if %errorlevel%==2 set javaVersion=11
if %errorlevel%==3 set javaVersion=8

set "find=graalvm-ee-java%javaVersion%-windows-%PROCESSOR_ARCHITECTURE%"

:: Check for internet
ping -n 1 github.com >nul 2>&1 || (
	echo You need an internet connection that works to use this script.
	echo Alternatively, something may be blocking GitHub connections.
	pause
	exit /b 1
)

:curlGetURL
cls
where curl >nul 2>&1 || (goto powershellGetURL)
:: Delete old temp file with URL
del /f /q "%temp%\pathPSGraalVMTemp.txt" >nul 2>&1
:: Get GraalVM URL from https://github.com/brucethemoose/Minecraft-Performance-Flags-Benchmarks
for /f "tokens=5 delims= " %%a in ('curl -s https://raw.githubusercontent.com/brucethemoose/Minecraft-Performance-Flags-Benchmarks/main/README.md ^| find /I "%find%"') do (set url=%%a)
echo %url% | find /I "%find%" >nul 2>&1
if not %errorlevel%==0 (goto powershellGetURL) else (goto openFolderPicker)

:powershellGetURL
:: Delete old temp file with URL
del /f /q "%temp%\pathPSGraalVMTemp.txt" >nul 2>&1
:: Get GraalVM URL from https://github.com/brucethemoose/Minecraft-Performance-Flags-Benchmarks
for /f "tokens=5 delims= " %%a in ('powershell -NoProfile -NonInteractive irm https://raw.githubusercontent.com/brucethemoose/Minecraft-Performance-Flags-Benchmarks/main/README.md ^| find /I "%find%"') do (set url=%%a)
echo %url% | find /I "%find%" >nul 2>&1
if not %errorlevel%==0 (goto githubFail) else (goto openFolderPicker)

:openFolderPicker
:: Open folder picker
start "" /min "%~f0" folderPick
:loop
if not exist "%temp%\pathPSGraalVMTemp.txt" (
	timeout /nobreak 1 > nul
	goto loop
)

:: Get folder path from temp folder picker file
for /f "tokens=*" %%a in ('type "%temp%\pathPSGraalVMTemp.txt"') do (set folderPath=%%a)
if not exist "%folderPath%" (
	echo Either:
	echo 1^) No folder was selected ^(dialog was closed^)
	echo 2^) The folder selected was invalid somehow
	echo 3^) The folder picker did not work ^(make sure you have PowerShell 5.1 installed^)
	echo]
	echo Press any key to retry...
	pause > nul
	cls
	del /f /q "%temp%\pathPSGraalVMTemp.txt" >nul 2>&1
	goto folderPicker
)
:: Get the file name of the zip downloaded
set tempUrl=%url:/= %
for %%a in (%tempUrl%) do (set fileName=%%a)

echo File name: %fileName%
echo Folder path: %folderPath%
echo URL: %url%
echo Java version: %javaVersion%

echo]
choice /c:yn /n /m "Continue? [Y/N] "
if %errorlevel%==2 exit /b 1
echo]

:: Uses cURL with a progress bar to download GraalVM Enterprise
echo Downloading GraalVM Enterprise Java %javaVersion%...
where curl >nul 2>&1 || (goto powershellDownload)
curl -L# "%url%" -o "%folderPath%\%fileName%"
if not %errorlevel%==0 (
	echo Failed downloading GraalVM using cURL!
	echo Try downloading GraalVM in your browser with this URL: %url%
	echo If this URL seems valid and matches the URL in the GitHub repo with the links, but it still doesn't download, report it on the GitHub repo.
	echo]
	echo GitHub repo: https://github.com/brucethemoose/Minecraft-Performance-Flags-Benchmarks
	echo]
	echo Press any key to attempt to download with PowerShell...
	pause > nul
	goto powershellDownload
)
goto extract

:powershellDownload
:: Use PowerShell with Invoke-WebRequest to download GraalVM, if cURL does not work or does not exist
powershell -NoProfile iwr "$env:url" -o "$env:folderpath\$env:filename"
if not %errorlevel%==0 (
	echo Failed downloading GraalVM using PowerShell!
	echo Try downloading GraalVM in your browser with this URL: %url%
	echo If this URL seems valid and matches the URL in the GitHub repo with the links, but it still doesn't download, report it on the GitHub repo.
	echo]
	echo GitHub repo: https://github.com/brucethemoose/Minecraft-Performance-Flags-Benchmarks
	echo]
	echo Press any key to exit...
	pause > nul
	exit /b 1
)
goto extract

:extract
:: By default the zip has a folder in it (with GraalVM inside) with the Java version, EE/CE and the Graal version
:: Asks the user if they want to move all of the files out of that folder once extracted into the folder they extracted
echo]
echo What do you want to do?
echo 1) Extract all of the contents of the GraalVM JDK directly into your folder
echo 2) Extract the contents of the GraalVM JDK into a folder inside of your folder ^(e.g. graalvm-ee-java8-21.3.5^)
echo]
choice /c:12 /n /m "Press 1 or 2: "
if %errorlevel%==1 set direct=true
if %errorlevel%==2 set direct=false

:: Find 7z executable
:: If the user does not have 7z, use PowerShell to extract
where 7z >nul 2>&1
if not %errorlevel%==0 (
	if not exist "%ProgramFiles%\7-Zip\7z.exe" (
		goto powershellExtract
	) else (
		set zip="%ProgramFiles%\7-Zip\7z.exe"
	)
) else (
	set "zip=7z.exe"
)

:: Use 7z to extract zip
%zip% x "%folderPath%\%fileName%" -o"%folderPath%" -y -slp -bso0 -bsp0
goto finish

:powershellExtract
:: Use PowerShell to extract zip, if 7z does not exist
powershell -NoProfile Expand-Archive -LiteralPath "$env:folderPath\$env:fileName" -DestinationPath "$env:folderPath"
goto finish
 
:finish
:: If the user selected the direct option, do that here
set "fileNameNoExtension=%fileName:.zip=%"
set "graalFolder=%fileNameNoExtension:windows-amd64-=%"
:: Robocopy is used as it's the most advanced and xcopy had some errors
if "%direct%"=="true" (
	robocopy "%folderPath%\%graalFolder%" "%folderPath%" "*.*" /E /DCOPY:DATE /COPY:DATO /MOVE /J /NJH /NJS /NDL /NFL /NS /NC /IM /IT
)
:: Delete zip
del /f /q "%folderPath%\%fileName%" > nul
echo]
echo Completed!
pause
exit /b 0

:githubFail
echo]
echo It seems like the source for the GraalVM links is currently down, deleted or generally unavaliable.
echo Make sure that you can access this GitHub page: https://github.com/brucethemoose/Minecraft-Performance-Flags-Benchmarks
echo]
echo If not, it may be blocked by your network or something similar.
echo Alternatively, the README.md file could no longer include the GraalVM EE links.
pause
exit /b 1

:folderPick
:: Credit to https://stackoverflow.com/a/66823582
:: Vista style folder picker that uses C# in PowerShell
:: A bit weird for a batch script, but it works well!
(for %%I in ("%~f0";%*) do @echo(%%~I) | powershell.exe -noprofile -command "$argv = $input | ?{$_}; iex (${%~f0} | out-string)" && exit
: end batch / begin powershell #>
$path = $args[0]
$title = $args[1]
$message = $args[2]

$source = @'
using System;
using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;
/// <summary>
/// Present the Windows Vista-style open file dialog to select a folder. Fall back for older Windows Versions
/// </summary>
#pragma warning disable 0219, 0414, 0162
public class FolderSelectDialog {
    private string _initialDirectory;
    private string _title;
    private string _message;
    private string _fileName = "";
    
    public string InitialDirectory {
        get { return string.IsNullOrEmpty(_initialDirectory) ? Environment.CurrentDirectory : _initialDirectory; }
        set { _initialDirectory = value; }
    }
    public string Title {
        get { return _title ?? "Select a folder"; }
        set { _title = value; }
    }
    public string Message {
        get { return _message ?? _title ?? "Select a folder"; }
        set { _message = value; }
    }
    public string FileName { get { return _fileName; } }

    public FolderSelectDialog(string defaultPath="MyComputer", string title="Select a folder", string message=""){
        InitialDirectory = defaultPath;
        Title = title;
        Message = message;
    }
    
    public bool Show() { return Show(IntPtr.Zero); }

    /// <param name="hWndOwner">Handle of the control or window to be the parent of the file dialog</param>
    /// <returns>true if the user clicks OK</returns>
    public bool Show(IntPtr? hWndOwnerNullable=null) {
        IntPtr hWndOwner = IntPtr.Zero;
        if(hWndOwnerNullable!=null)
            hWndOwner = (IntPtr)hWndOwnerNullable;
        if(Environment.OSVersion.Version.Major >= 6){
            try{
                var resulta = VistaDialog.Show(hWndOwner, InitialDirectory, Title, Message);
                _fileName = resulta.FileName;
                return resulta.Result;
            }
            catch(Exception){
                var resultb = ShowXpDialog(hWndOwner, InitialDirectory, Title, Message);
                _fileName = resultb.FileName;
                return resultb.Result;
            }
        }
        var result = ShowXpDialog(hWndOwner, InitialDirectory, Title, Message);
        _fileName = result.FileName;
        return result.Result;
    }

    private struct ShowDialogResult {
        public bool Result { get; set; }
        public string FileName { get; set; }
    }

    private static ShowDialogResult ShowXpDialog(IntPtr ownerHandle, string initialDirectory, string title, string message) {
        var folderBrowserDialog = new FolderBrowserDialog {
            Description = message,
            SelectedPath = initialDirectory,
            ShowNewFolderButton = true
        };
        var dialogResult = new ShowDialogResult();
        if (folderBrowserDialog.ShowDialog(new WindowWrapper(ownerHandle)) == DialogResult.OK) {
            dialogResult.Result = true;
            dialogResult.FileName = folderBrowserDialog.SelectedPath;
        }
        return dialogResult;
    }

    private static class VistaDialog {
        private const string c_foldersFilter = "Folders|\n";
        
        private const BindingFlags c_flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        private readonly static Assembly s_windowsFormsAssembly = typeof(FileDialog).Assembly;
        private readonly static Type s_iFileDialogType = s_windowsFormsAssembly.GetType("System.Windows.Forms.FileDialogNative+IFileDialog");
        private readonly static MethodInfo s_createVistaDialogMethodInfo = typeof(OpenFileDialog).GetMethod("CreateVistaDialog", c_flags);
        private readonly static MethodInfo s_onBeforeVistaDialogMethodInfo = typeof(OpenFileDialog).GetMethod("OnBeforeVistaDialog", c_flags);
        private readonly static MethodInfo s_getOptionsMethodInfo = typeof(FileDialog).GetMethod("GetOptions", c_flags);
        private readonly static MethodInfo s_setOptionsMethodInfo = s_iFileDialogType.GetMethod("SetOptions", c_flags);
        private readonly static uint s_fosPickFoldersBitFlag = (uint) s_windowsFormsAssembly
            .GetType("System.Windows.Forms.FileDialogNative+FOS")
            .GetField("FOS_PICKFOLDERS")
            .GetValue(null);
        private readonly static ConstructorInfo s_vistaDialogEventsConstructorInfo = s_windowsFormsAssembly
            .GetType("System.Windows.Forms.FileDialog+VistaDialogEvents")
            .GetConstructor(c_flags, null, new[] { typeof(FileDialog) }, null);
        private readonly static MethodInfo s_adviseMethodInfo = s_iFileDialogType.GetMethod("Advise");
        private readonly static MethodInfo s_unAdviseMethodInfo = s_iFileDialogType.GetMethod("Unadvise");
        private readonly static MethodInfo s_showMethodInfo = s_iFileDialogType.GetMethod("Show");

        public static ShowDialogResult Show(IntPtr ownerHandle, string initialDirectory, string title, string description) {
            var openFileDialog = new OpenFileDialog {
                AddExtension = false,
                CheckFileExists = false,
                DereferenceLinks = true,
                Filter = c_foldersFilter,
                InitialDirectory = initialDirectory,
                Multiselect = false,
                Title = title
            };

            var iFileDialog = s_createVistaDialogMethodInfo.Invoke(openFileDialog, new object[] { });
            s_onBeforeVistaDialogMethodInfo.Invoke(openFileDialog, new[] { iFileDialog });
            s_setOptionsMethodInfo.Invoke(iFileDialog, new object[] { (uint) s_getOptionsMethodInfo.Invoke(openFileDialog, new object[] { }) | s_fosPickFoldersBitFlag });
            var adviseParametersWithOutputConnectionToken = new[] { s_vistaDialogEventsConstructorInfo.Invoke(new object[] { openFileDialog }), 0U };
            s_adviseMethodInfo.Invoke(iFileDialog, adviseParametersWithOutputConnectionToken);

            try {
                int retVal = (int) s_showMethodInfo.Invoke(iFileDialog, new object[] { ownerHandle });
                return new ShowDialogResult {
                    Result = retVal == 0,
                    FileName = openFileDialog.FileName
                };
            }
            finally {
                s_unAdviseMethodInfo.Invoke(iFileDialog, new[] { adviseParametersWithOutputConnectionToken[1] });
            }
        }
    }

    // Wrap an IWin32Window around an IntPtr
    private class WindowWrapper : IWin32Window {
        private readonly IntPtr _handle;
        public WindowWrapper(IntPtr handle) { _handle = handle; }
        public IntPtr Handle { get { return _handle; } }
    }
    
    public string getPath(){
        if (Show()){
            return FileName;
        }
        return "";
    }
}
'@
Add-Type -Language CSharp -TypeDefinition $source -ReferencedAssemblies ("System.Windows.Forms", "System.ComponentModel.Primitives")
$Path = ([FolderSelectDialog]::new("$ENV:userprofile\Documents", "Select an Output Path", "Select an output path for GraalVM")).getPath()
$Path.Trim('"') > "$env:temp\pathPSGraalVMTemp.txt"
exit