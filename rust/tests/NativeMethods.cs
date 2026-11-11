// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System;
using System.Runtime.InteropServices;

namespace PowerShell.Native.Tests
{
    [StructLayout(LayoutKind.Sequential)]
    public struct CommonStat
    {
        public long Inode;
        public int Mode, UserId, GroupId, HardlinkCount;
        public long Size, AccessTime, ModifiedTime, ChangeTime, BlockSize;
        public int DeviceId, NumberOfBlocks, IsDirectory, IsFile, IsSymbolicLink;
        public int IsBlockDevice, IsCharacterDevice, IsNamedPipe, IsSocket;
        public int IsSetUid, IsSetGid, IsSticky;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PrivateTm
    {
        public int Second, Minute, Hour, Day, Month, Year, WeekDay, YearDay, IsDst;
    }

    public static class NativeMethods
    {
        private const string Library = "rust-psl-native-tests";
        private static IntPtr handle;

        public static void Load(string path)
        {
            handle = NativeLibrary.Load(path);
            NativeLibrary.SetDllImportResolver(typeof(NativeMethods).Assembly,
                (name, assembly, searchPath) => name == Library ? handle : IntPtr.Zero);
            // P/Invoke caches function addresses; retain the module until process exit.
        }

        public static IntPtr Export(string name) => NativeLibrary.GetExport(handle, name);

        [DllImport(Library)] public static extern int GetCurrentProcessId();
        [DllImport(Library)] public static extern int GetCurrentThreadId();
        [DllImport(Library)] public static extern int GetPPid(int pid);
        [DllImport(Library)] public static extern int GetErrorCategory(int error);
        [DllImport(Library)] [return: MarshalAs(UnmanagedType.LPUTF8Str)]
        public static extern string GetComputerName();
        [DllImport(Library)] [return: MarshalAs(UnmanagedType.LPUTF8Str)]
        public static extern string GetPwUid(uint uid);
        [DllImport(Library)] [return: MarshalAs(UnmanagedType.LPUTF8Str)]
        public static extern string GetGrGid(uint gid);
        [DllImport(Library)] [return: MarshalAs(UnmanagedType.LPUTF8Str)]
        public static extern string GetUserFromPid(int pid);
        [DllImport(Library)] [return: MarshalAs(UnmanagedType.LPUTF8Str)]
        public static extern string GetFileOwner([MarshalAs(UnmanagedType.LPUTF8Str)] string path);
        [DllImport(Library)] [return: MarshalAs(UnmanagedType.LPUTF8Str)]
        public static extern string FollowSymLink([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

        [DllImport(Library, SetLastError = true)]
        public static extern int GetCommonStat([MarshalAs(UnmanagedType.LPUTF8Str)] string path, out CommonStat stat);
        [DllImport(Library, SetLastError = true)]
        public static extern int GetCommonLStat([MarshalAs(UnmanagedType.LPUTF8Str)] string path, out CommonStat stat);
        [DllImport(Library, SetLastError = true)]
        public static extern int GetStat([MarshalAs(UnmanagedType.LPUTF8Str)] string path, IntPtr stat);
        [DllImport(Library, SetLastError = true)]
        public static extern int GetLStat([MarshalAs(UnmanagedType.LPUTF8Str)] string path, IntPtr stat);
        [DllImport(Library, SetLastError = true)]
        public static extern int GetLinkCount([MarshalAs(UnmanagedType.LPUTF8Str)] string path, out int count);
        [DllImport(Library, SetLastError = true)]
        public static extern int GetInodeData([MarshalAs(UnmanagedType.LPUTF8Str)] string path, out ulong device, out ulong inode);
        [DllImport(Library, SetLastError = true)]
        public static extern int CreateHardLink([MarshalAs(UnmanagedType.LPUTF8Str)] string link, [MarshalAs(UnmanagedType.LPUTF8Str)] string target);
        [DllImport(Library, SetLastError = true)]
        public static extern int CreateSymLink([MarshalAs(UnmanagedType.LPUTF8Str)] string link, [MarshalAs(UnmanagedType.LPUTF8Str)] string target);

        [DllImport(Library, SetLastError = true)] [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool IsFile([MarshalAs(UnmanagedType.LPUTF8Str)] string path);
        [DllImport(Library, SetLastError = true)] [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool IsDirectory([MarshalAs(UnmanagedType.LPUTF8Str)] string path);
        [DllImport(Library, SetLastError = true)] [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool IsSymLink([MarshalAs(UnmanagedType.LPUTF8Str)] string path);
        [DllImport(Library, SetLastError = true)] [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool IsExecutable([MarshalAs(UnmanagedType.LPUTF8Str)] string path);
        [DllImport(Library, SetLastError = true)] [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool IsSameFileSystemItem([MarshalAs(UnmanagedType.LPUTF8Str)] string first, [MarshalAs(UnmanagedType.LPUTF8Str)] string second);

        [DllImport(Library, SetLastError = true)] public static extern int SetDate(IntPtr date);
        [DllImport(Library, SetLastError = true)] [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool KillProcess(int pid);
        [DllImport(Library, SetLastError = true)]
        public static extern int WaitPid(int pid, [MarshalAs(UnmanagedType.I1)] bool nohang);
        [DllImport(Library, SetLastError = true)]
        public static extern int ForkAndExecProcess(IntPtr file, IntPtr argv, IntPtr envp, IntPtr cwd,
            int stdin, int stdout, int stderr, int flags, out int child, out int input, out int output, out int error);
        [DllImport(Library)] public static extern void Native_OpenLog([MarshalAs(UnmanagedType.LPUTF8Str)] string ident, int facility);
        [DllImport(Library)] public static extern void Native_SysLog(int priority, [MarshalAs(UnmanagedType.LPUTF8Str)] string message);
        [DllImport(Library)] public static extern void Native_CloseLog();
        [DllImport("libc")] public static extern uint getuid();
        [DllImport("libc")] public static extern uint getgid();
    }
}
