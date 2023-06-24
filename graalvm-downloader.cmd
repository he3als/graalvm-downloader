<# : batch portion
@echo off
if "%1"=="-ngen" (
	fltmc >nul 2>&1 || (
		echo Administrator privileges are required for NGEN.
		PowerShell Start -Verb RunAs '%0' -ArgumentList '-ngen' 2> nul || (
			echo To optimise PowerShell with NGEN, you must run this script as admin.
			pause & exit /b 1
		)
		exit /b 0
	)
	set ngen=true
)

set "psScript=%~f0" & powershell -nop -c "if (Test-Path """env:ngen""") { $ngen = $true }; Get-Content """$env:psScript""" -Raw | iex" & exit /b
: end batch / begin PowerShell #>

$version = "1.0.0"
$host.ui.RawUI.WindowTitle = "GraalVM Downloader $version"

function Exit-Prompt {
	Start-Sleep 0.75; Write-Host "Press any key to exit... " -NoNewLine
	$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

# ngen script to optimise PowerShell startup time
# why is this relevant to a GraalVM script? it isn't, i just wanted to include it as a tip
# https://stackoverflow.com/a/59343705
if ($ngen) {
	Write-Warning "This will optimise PowerShell startup time by compiling the .NET libraries it uses, this might take a while and may use significant CPU usage. Starting in 5 seconds..."
	Start-Sleep 5
	$env:PATH = [Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
	[AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object {
		$path = $_.Location
		if ($path) { 
			$name = Split-Path $path -Leaf
			Write-Host -ForegroundColor Yellow "`r`nRunning ngen.exe on '$name'"
			ngen.exe install $path /nologo
		}
	}
	Write-Host "`nCompleted, PowerShell should startup much faster now." -ForegroundColor Green
	Exit-Prompt
	exit 0
}

if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
    Write-Host "GraalVM on Windows is only supported on AMD64 CPUs."
	Exit-Prompt
    exit 1
}

ping www.oracle.com -n 1 | Out-Null
if (!($?)) {
	Write-Host "Your computer can't connect/ping to Oracle's servers.
This means that you are either offline or that there are network restrictions, so this script can't work.`n"
	Exit-Prompt
	exit 1
}

do {
	Clear-Host; Write-Host "======== Select a Version ========`n" -ForegroundColor Yellow
	Write-Host "1) GraalVM Java 20
2) GraalVM Java 17
3) GraalVM EE Java 11
4) GraalVM EE Java 8"

	$release = "Current Release"
	$selection = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
	switch ($selection.Character) {
		1 {
			$javaVersion = "20"
		} 2 {
			$javaVersion = "17"
		} 3 {
			$release = "Mid-Term-Support Release"
			$javaVersion = "11"
		} 4 {
			$release = "Long-Term-Support Release"
			$javaVersion = "8"
		}
	}
} until ($javaVersion)

# get latest version number for specified GraalVM version
$versionsApi = Invoke-WebRequest "https://www.oracle.com/a/tech/docs/graalvm-downloads.json" | ConvertFrom-Json
$edition = $versionsApi | ForEach-Object { $_.PSObject.Properties } | Where-Object { $_.Value.SubTitle -like "*$release*" } | Sort-Object { $_.Name } | Select-Object -First 1
$latestVersion = $edition.Value.Releases | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name -Last 1
$latestVersionUnderscores = $latestVersion.Replace('.','_')

# get download link
if ($release -ne "Current Release") {
	$downloadUrl = "https://oca.opensource.oracle.com/gds/GRAALVM_EE_JAVA$javaVersion`_$latestVersionUnderscores/graalvm-ee-java$javaVersion-windows-amd64-$latestVersion.zip"
} else {
	$downloadUrl = "https://download.oracle.com/java/$javaVersion/latest/jdk-$javaVersion`_windows-x64_bin.zip"
}

# get hash for specified GraalVM version
# used for checking if %temp% already has an identical GraalVM ZIP
if ($release -ne "Current Release") {
	$graalVersionApi = Invoke-WebRequest "https://www.oracle.com/a/tech/docs/graalvm-$latestVersion.json" | ConvertFrom-Json
	if ($javaVersion -eq "8") {$packageName = "Core"} else {$packageName = "JDK"}
	$hash = $graalVersionApi.Packages.$packageName.Files."$latestVersion-Windows-x86-$javaVersion".Hash | Select-Object -Last 1
} else {
	$hash = (Invoke-WebRequest "$downloadUrl.sha256").Content
}

Clear-Host; Write-Warning "Opening folder picker..."

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
$path = ([FolderSelectDialog]::new("$ENV:userprofile\Documents", "Select an Output Path", "Select an output path for GraalVM")).getPath()

$graalFolderName = "graalvm-jdk$javaVersion-$latestVersion"

$newFolder = "$path\$graalFolderName"
if (Test-Path "$newFolder") {
	$folderNum = 1
	while (Test-Path "$newFolder") {
		$folderNum = $folderNum + 1
		$newFolder = "$path\$graalFolderName ($folderNum)"
	}
}

do {
	Clear-Host; Write-Host "======== What would you like to do? ========" -ForegroundColor Yellow
	Write-Host "1) Extract GraalVM JDK directly into your selected folder
2) Extract GraalVM JDK into a new folder inside of your folder`n"

	Write-Host "Here's what the resulting paths to javaw.exe for each option would look like:" -ForegroundColor Green
	Write-Host "- $path\bin\javaw.exe
- $newFolder\bin\javaw.exe"

	$selection = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
	switch ($selection.Character) {
		1 {
			$folder = "$path"
		} 2 {
			$folder = "$newFolder"
		}
	}
} until ($folder)

# download graalvm
$zip = "$env:temp\$graalFolderName.zip"

if (!((Test-Path $zip) -and ((Get-FileHash $zip).Hash -eq $hash))) {
	Clear-Host; Write-Warning "Downloading GraalVM from $downloadUrl"
	$download = Invoke-WebRequest $downloadUrl -o $zip -UseBasicParsing
	if (!($?)) {
		Write-Host "Failed to download GraalVM!"
		Exit-Prompt
		exit 1
	}
} else {
	Clear-Host; Write-Warning "Found identical GraalVM ZIP in %temp% already, using that instead of redownloading..."
}

Write-Warning "Extracing GraalVM to the specified folder..."

# get folder name inside of zip
[void][Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem')
$files = [IO.Compression.ZipFile]::OpenRead($zip).Entries
$folderInZip = (($files | Where FullName -match '/' | Select -First 1).Fullname -Split '/')[0]

Expand-Archive -LiteralPath $zip -DestinationPath "$folder"
Move-Item -Path "$folder\$folderInZip\*" -Destination "$folder" -Force
Remove-Item "$folder\$folderInZip" -Force -Recurse

Write-Host "`nCompleted!

Tip: " -ForegroundColor Green -NoNewLine
Write-Host "If you want PowerShell to startup faster for this script, other scripts and the shell, run this script with -ngen.`n"
Exit-Prompt