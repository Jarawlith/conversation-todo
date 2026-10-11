using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace ConversationTodo {
    public static class Hotkey {
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
        public static bool IsDown(int key) { return (GetAsyncKeyState(key) & 0x8000) != 0; }
    }
    public static class MouseShortcut {
        [StructLayout(LayoutKind.Sequential)] struct MouseData {
            public int x, y; public uint data, flags, time; public UIntPtr extra;
        }
        delegate IntPtr MouseCallback(int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, MouseCallback callback, IntPtr module, uint thread);
        [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
        [DllImport("kernel32.dll", CharSet=CharSet.Auto)] static extern IntPtr GetModuleHandle(string name);
        static readonly MouseCallback callback = OnMouse;
        static IntPtr hook, window;
        static int button;
        static uint modifiers;
        public static bool Pressed { get; private set; }
        public static bool Enable(IntPtr hwnd, int key, uint mods) {
            Disable(); window=hwnd; button=key == 5 ? 1 : 2; modifiers=mods;
            hook=SetWindowsHookEx(14, callback, GetModuleHandle(null), 0);
            return hook != IntPtr.Zero;
        }
        public static void Disable() {
            if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
            hook=IntPtr.Zero; Pressed=false; button=0;
        }
        static uint CurrentModifiers() {
            uint result=0;
            if (Hotkey.IsDown(18)) result |= 1;
            if (Hotkey.IsDown(17)) result |= 2;
            if (Hotkey.IsDown(16)) result |= 4;
            if (Hotkey.IsDown(91) || Hotkey.IsDown(92)) result |= 8;
            return result;
        }
        // Only post a message here: microphone and recognition work run outside the hook.
        static bool HandleButton(int message, int selected, uint mods) {
            if (selected != button || button == 0) return false;
            if (message == 0x20B && (Pressed || mods == modifiers)) {
                if (!Pressed) { Pressed=true; PostMessage(window, 0x8001, IntPtr.Zero, IntPtr.Zero); }
                return true;
            }
            if (message == 0x20C && Pressed) { Pressed=false; return true; }
            return false;
        }
        static IntPtr OnMouse(int code, IntPtr message, IntPtr pointer) {
            if (code >= 0 && (message.ToInt32() == 0x20B || message.ToInt32() == 0x20C)) {
                var data=(MouseData)Marshal.PtrToStructure(pointer, typeof(MouseData));
                if (HandleButton(message.ToInt32(), (int)(data.data >> 16), CurrentModifiers())) return new IntPtr(1);
            }
            return CallNextHookEx(hook, code, message, pointer);
        }
    }
    public sealed class Microphone : IDisposable {
        [StructLayout(LayoutKind.Sequential, Pack=2)] struct Format {
            public ushort tag, channels; public uint rate, bytesPerSecond;
            public ushort alignment, bits, extra;
        }
        [StructLayout(LayoutKind.Sequential)] struct Header {
            public IntPtr data; public uint length, recorded; public UIntPtr user;
            public uint flags, loops; public IntPtr next; public UIntPtr reserved;
        }
        delegate void WaveCallback(IntPtr device, uint message, UIntPtr instance, IntPtr header, IntPtr unused);
        [DllImport("winmm.dll")] static extern uint waveInOpen(out IntPtr device, uint id, ref Format format, WaveCallback callback, UIntPtr instance, uint flags);
        [DllImport("winmm.dll")] static extern uint waveInPrepareHeader(IntPtr device, IntPtr header, uint size);
        [DllImport("winmm.dll")] static extern uint waveInUnprepareHeader(IntPtr device, IntPtr header, uint size);
        [DllImport("winmm.dll")] static extern uint waveInAddBuffer(IntPtr device, IntPtr header, uint size);
        [DllImport("winmm.dll")] static extern uint waveInStart(IntPtr device);
        [DllImport("winmm.dll")] static extern uint waveInReset(IntPtr device);
        [DllImport("winmm.dll")] static extern uint waveInClose(IntPtr device);
        readonly object sync = new object();
        readonly MemoryStream audio = new MemoryStream();
        readonly List<IntPtr> headers = new List<IntPtr>();
        readonly WaveCallback callback;
        IntPtr device;
        volatile bool stopping;
        readonly uint size = (uint)Marshal.SizeOf(typeof(Header));
        public Microphone() { callback = OnWave; }
        static void Check(uint result) {
            if (result != 0) throw new InvalidOperationException("无法打开麦克风（" + result + "）。请检查 Windows 麦克风权限和默认输入设备。");
        }
        public void Start() {
            if (device != IntPtr.Zero) throw new InvalidOperationException("Recording already started");
            stopping = false;
            var format = new Format {tag=1, channels=1, rate=16000, bytesPerSecond=32000, alignment=2, bits=16};
            Check(waveInOpen(out device, 0xFFFFFFFF, ref format, callback, UIntPtr.Zero, 0x30000));
            try {
                for (int i=0; i<8; i++) {
                    var header = new Header {data=Marshal.AllocHGlobal(4000), length=4000};
                    IntPtr pointer = Marshal.AllocHGlobal((int)size);
                    Marshal.StructureToPtr(header, pointer, false); headers.Add(pointer);
                    Check(waveInPrepareHeader(device, pointer, size));
                    Check(waveInAddBuffer(device, pointer, size));
                }
                Check(waveInStart(device));
            } catch { Dispose(); throw; }
        }
        void OnWave(IntPtr handle, uint message, UIntPtr instance, IntPtr pointer, IntPtr unused) {
            if (message != 0x3C0) return;
            var header = (Header)Marshal.PtrToStructure(pointer, typeof(Header));
            if (header.recorded > 0) {
                byte[] bytes = new byte[header.recorded]; Marshal.Copy(header.data, bytes, 0, bytes.Length);
                lock(sync) { if (audio.Length < 32000 * 120) audio.Write(bytes, 0, bytes.Length); }
            }
            if (!stopping) waveInAddBuffer(handle, pointer, size);
        }
        public byte[] Stop() { Dispose(); lock(sync) { return audio.ToArray(); } }
        public void Dispose() {
            if (device == IntPtr.Zero) return;
            stopping = true; waveInReset(device);
            foreach (IntPtr pointer in headers) {
                waveInUnprepareHeader(device, pointer, size);
                var header = (Header)Marshal.PtrToStructure(pointer, typeof(Header));
                Marshal.FreeHGlobal(header.data); Marshal.FreeHGlobal(pointer);
            }
            headers.Clear(); waveInClose(device); device = IntPtr.Zero;
            GC.KeepAlive(callback);
        }
    }
}
