using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace DocumentStudio.Shell;

/// <summary>
/// COM Explorer commands for the Windows 11 modern context menu (sparse package).
/// Classic Win10-style registry verbs alone do not appear in the Win11 primary menu.
/// </summary>
internal static class NativeMethods
{
    public const int S_OK = 0;
    public const int S_FALSE = 1;
    public const int E_NOTIMPL = unchecked((int)0x80004001);
    public const int E_FAIL = unchecked((int)0x80004005);
    public const int E_INVALIDARG = unchecked((int)0x80070057);
    public const int E_POINTER = unchecked((int)0x80004003);

    public const uint ECS_ENABLED = 0;
    public const uint ECF_DEFAULT = 0;
    public const uint ECF_HASSUBCOMMANDS = 0x1;
    public const uint SIGDN_FILESYSPATH = 0x80058000;

    [DllImport("ole32.dll")]
    public static extern int CoCreateInstance(
        in Guid rclsid,
        IntPtr pUnkOuter,
        uint dwClsContext,
        in Guid riid,
        out IntPtr ppv);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHCreateItemFromParsingName(
        string pszPath,
        IntPtr pbc,
        in Guid riid,
        out IntPtr ppv);
}

[ComImport]
[Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellItem
{
    void BindToHandler(IntPtr pbc, in Guid bhid, in Guid riid, out IntPtr ppv);
    void GetParent(out IShellItem ppsi);
    void GetDisplayName(uint sigdnName, out IntPtr ppszName);
    void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
    void Compare(IShellItem psi, uint hint, out int piOrder);
}

[ComImport]
[Guid("b63ea76d-1f85-456f-a19c-48159efa858b")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellItemArray
{
    void BindToHandler(IntPtr pbc, in Guid bhid, in Guid riid, out IntPtr ppvOut);
    void GetPropertyStore(int flags, in Guid riid, out IntPtr ppv);
    void GetPropertyDescriptionList(in Guid keyType, in Guid riid, out IntPtr ppv);
    void GetAttributes(int AttribFlags, uint sfgaoMask, out uint psfgaoAttribs);
    void GetCount(out uint pdwNumItems);
    void GetItemAt(uint dwIndex, out IShellItem ppsi);
    void EnumItems(out IntPtr ppenumShellItems);
}

[ComImport]
[Guid("a08ce4d0-fa25-44ab-b57c-c7b1ce4549ce")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IExplorerCommand
{
    [PreserveSig]
    int GetTitle(IShellItemArray? psiItemArray, out IntPtr ppszName);

    [PreserveSig]
    int GetIcon(IShellItemArray? psiItemArray, out IntPtr ppszIcon);

    [PreserveSig]
    int GetToolTip(IShellItemArray? psiItemArray, out IntPtr ppszInfotip);

    [PreserveSig]
    int GetCanonicalName(out Guid pguidCommandName);

    [PreserveSig]
    int GetState(IShellItemArray? psiItemArray, [MarshalAs(UnmanagedType.Bool)] bool fOkToBeSlow, out uint pCmdState);

    [PreserveSig]
    int Invoke(IShellItemArray? psiItemArray, IntPtr pbc);

    [PreserveSig]
    int GetFlags(out uint pFlags);

    [PreserveSig]
    int EnumSubCommands(out IEnumExplorerCommand? ppEnum);
}

[ComImport]
[Guid("a88826f8-186f-4987-aae3-36671d1bf46b")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IEnumExplorerCommand
{
    [PreserveSig]
    int Next(uint celt, [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] IExplorerCommand[] pUICommand, out uint pceltFetched);

    [PreserveSig]
    int Skip(uint celt);

    [PreserveSig]
    int Reset();

    [PreserveSig]
    int Clone(out IEnumExplorerCommand ppenum);
}

internal static class ShellPaths
{
    public static string? FindAppExe()
    {
        try
        {
            var dll = typeof(ShellPaths).Assembly.Location;
            var dir = Path.GetDirectoryName(dll);
            if (!string.IsNullOrEmpty(dir))
            {
                var beside = Path.Combine(dir, "document_studio.exe");
                if (File.Exists(beside)) return beside;
                var parent = Path.GetDirectoryName(dir);
                if (!string.IsNullOrEmpty(parent))
                {
                    var up = Path.Combine(parent, "document_studio.exe");
                    if (File.Exists(up)) return up;
                }
            }
        }
        catch { }

        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\App Paths\document_studio.exe");
            var path = key?.GetValue(null) as string;
            if (!string.IsNullOrEmpty(path) && File.Exists(path)) return path;
        }
        catch { }

        return null;
    }

    public static List<string> GetFilePaths(IShellItemArray? items)
    {
        var list = new List<string>();
        if (items is null) return list;
        items.GetCount(out var count);
        for (uint i = 0; i < count; i++)
        {
            items.GetItemAt(i, out var item);
            item.GetDisplayName(NativeMethods.SIGDN_FILESYSPATH, out var ptr);
            if (ptr != IntPtr.Zero)
            {
                try
                {
                    var path = Marshal.PtrToStringUni(ptr);
                    if (!string.IsNullOrEmpty(path)) list.Add(path);
                }
                finally
                {
                    Marshal.FreeCoTaskMem(ptr);
                }
            }
        }
        return list;
    }

    public static int Launch(string? tool, IShellItemArray? items)
    {
        var exe = FindAppExe();
        if (exe is null) return NativeMethods.E_FAIL;
        var files = GetFilePaths(items);
        if (files.Count == 0) return NativeMethods.E_INVALIDARG;

        var args = new StringBuilder();
        if (!string.IsNullOrEmpty(tool))
        {
            args.Append("--tool ").Append(tool).Append(' ');
        }
        foreach (var f in files)
        {
            args.Append('"').Append(f).Append("\" ");
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = exe,
                Arguments = args.ToString().Trim(),
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(exe) ?? "",
            });
            return NativeMethods.S_OK;
        }
        catch
        {
            return NativeMethods.E_FAIL;
        }
    }

    public static IntPtr Alloc(string s) => Marshal.StringToCoTaskMemUni(s);
}

[ComVisible(false)]
public abstract class ExplorerCommandBase : IExplorerCommand
{
    protected abstract string Title { get; }
    protected abstract Guid CanonicalName { get; }
    protected virtual string? Tool => null;
    protected virtual bool HasSubCommands => false;

    public int GetTitle(IShellItemArray? psiItemArray, out IntPtr ppszName)
    {
        ppszName = ShellPaths.Alloc(Title);
        return NativeMethods.S_OK;
    }

    public int GetIcon(IShellItemArray? psiItemArray, out IntPtr ppszIcon)
    {
        var exe = ShellPaths.FindAppExe();
        if (exe is null)
        {
            ppszIcon = IntPtr.Zero;
            return NativeMethods.E_NOTIMPL;
        }
        ppszIcon = ShellPaths.Alloc(exe + ",0");
        return NativeMethods.S_OK;
    }

    public int GetToolTip(IShellItemArray? psiItemArray, out IntPtr ppszInfotip)
    {
        ppszInfotip = ShellPaths.Alloc(Title);
        return NativeMethods.S_OK;
    }

    public int GetCanonicalName(out Guid pguidCommandName)
    {
        pguidCommandName = CanonicalName;
        return NativeMethods.S_OK;
    }

    public int GetState(IShellItemArray? psiItemArray, bool fOkToBeSlow, out uint pCmdState)
    {
        pCmdState = NativeMethods.ECS_ENABLED;
        return NativeMethods.S_OK;
    }

    public virtual int Invoke(IShellItemArray? psiItemArray, IntPtr pbc) =>
        ShellPaths.Launch(Tool, psiItemArray);

    public int GetFlags(out uint pFlags)
    {
        pFlags = HasSubCommands ? NativeMethods.ECF_HASSUBCOMMANDS : NativeMethods.ECF_DEFAULT;
        return NativeMethods.S_OK;
    }

    public virtual int EnumSubCommands(out IEnumExplorerCommand? ppEnum)
    {
        ppEnum = null;
        return NativeMethods.E_NOTIMPL;
    }
}

[ComVisible(false)]
public sealed class EnumCommands : IEnumExplorerCommand
{
    private readonly IExplorerCommand[] _items;
    private int _index;

    public EnumCommands(IExplorerCommand[] items, int index = 0)
    {
        _items = items;
        _index = index;
    }

    public int Next(uint celt, IExplorerCommand[] pUICommand, out uint pceltFetched)
    {
        pceltFetched = 0;
        if (pUICommand is null || pUICommand.Length == 0) return NativeMethods.E_INVALIDARG;
        uint fetched = 0;
        while (fetched < celt && _index < _items.Length)
        {
            pUICommand[fetched] = _items[_index++];
            fetched++;
        }
        pceltFetched = fetched;
        return fetched == celt ? NativeMethods.S_OK : NativeMethods.S_FALSE;
    }

    public int Skip(uint celt)
    {
        _index = Math.Min(_items.Length, _index + (int)celt);
        return NativeMethods.S_OK;
    }

    public int Reset()
    {
        _index = 0;
        return NativeMethods.S_OK;
    }

    public int Clone(out IEnumExplorerCommand ppenum)
    {
        ppenum = new EnumCommands(_items, _index);
        return NativeMethods.S_OK;
    }
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000001")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class DocumentStudioRootCommand : ExplorerCommandBase
{
    protected override string Title => "Document Studio";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000001");
    protected override bool HasSubCommands => true;

    public override int Invoke(IShellItemArray? psiItemArray, IntPtr pbc) =>
        ShellPaths.Launch(null, psiItemArray);

    public override int EnumSubCommands(out IEnumExplorerCommand? ppEnum)
    {
        ppEnum = new EnumCommands([
            new OpenCommand(),
            new CompressCommand(),
            new ProtectCommand(),
            new UnlockCommand(),
            new SplitCommand(),
            new MergeCommand(),
            new OcrCommand(),
            new WatermarkCommand(),
        ]);
        return NativeMethods.S_OK;
    }
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000002")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class OpenCommand : ExplorerCommandBase
{
    protected override string Title => "Open with Document Studio";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000002");
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000003")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class CompressCommand : ExplorerCommandBase
{
    protected override string Title => "Compress PDF";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000003");
    protected override string? Tool => "compress";
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000004")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class ProtectCommand : ExplorerCommandBase
{
    protected override string Title => "Encrypt / protect PDF";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000004");
    protected override string? Tool => "protect";
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000005")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class UnlockCommand : ExplorerCommandBase
{
    protected override string Title => "Decrypt / unlock PDF";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000005");
    protected override string? Tool => "unlock";
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000006")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class SplitCommand : ExplorerCommandBase
{
    protected override string Title => "Split PDF";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000006");
    protected override string? Tool => "split";
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000007")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class MergeCommand : ExplorerCommandBase
{
    protected override string Title => "Merge PDFs…";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000007");
    protected override string? Tool => "merge";
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000008")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class OcrCommand : ExplorerCommandBase
{
    protected override string Title => "Make searchable (OCR)";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000008");
    protected override string? Tool => "ocr";
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-000000000009")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class WatermarkCommand : ExplorerCommandBase
{
    protected override string Title => "Add watermark";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-000000000009");
    protected override string? Tool => "watermark";
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-00000000000A")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class ImageRootCommand : ExplorerCommandBase
{
    protected override string Title => "Document Studio";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-00000000000A");
    protected override bool HasSubCommands => true;

    public override int Invoke(IShellItemArray? psiItemArray, IntPtr pbc) =>
        ShellPaths.Launch(null, psiItemArray);

    public override int EnumSubCommands(out IEnumExplorerCommand? ppEnum)
    {
        ppEnum = new EnumCommands([
            new OpenCommand(),
            new ImageEditCommand(),
        ]);
        return NativeMethods.S_OK;
    }
}

[ComVisible(true)]
[Guid("A1B2C3D4-E5F6-7890-ABCD-00000000000B")]
[ClassInterface(ClassInterfaceType.None)]
public sealed class ImageEditCommand : ExplorerCommandBase
{
    protected override string Title => "Edit with Document Studio";
    protected override Guid CanonicalName => new("A1B2C3D4-E5F6-7890-ABCD-00000000000B");
    protected override string? Tool => "images";
}
