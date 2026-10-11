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
