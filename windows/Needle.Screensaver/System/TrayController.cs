using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Windows.Interop;
using Needle.Screensaver.Native;

namespace Needle.Screensaver.SystemTray;

public sealed class TrayController : IDisposable
{
    private const int HotkeyId = 0x4E44; // "ND"

    private readonly NotifyIcon _notifyIcon;
    private readonly Icon _trayIcon;
    private readonly ToolStripMenuItem _statusItem;
    private HwndSource? _hotkeySource;
    private bool _hotkeyRegistered;
    private bool _disposed;

    public event Action? LockWithNeedleRequested;
    public event Action? PreviewRequested;
    public event Action? ExitRequested;

    public TrayController()
    {
        _trayIcon = CreateSparkleIcon();

        var menu = new ContextMenuStrip();

        _statusItem = new ToolStripMenuItem("Spotify: esperando…")
        {
            Enabled = false
        };
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());

        var lockItem = new ToolStripMenuItem("Bloquear con Needle (Ctrl+Alt+L)");
        lockItem.Click += (_, _) => LockWithNeedleRequested?.Invoke();
        menu.Items.Add(lockItem);

        var previewItem = new ToolStripMenuItem("Vista previa");
        previewItem.Click += (_, _) => PreviewRequested?.Invoke();
        menu.Items.Add(previewItem);

        menu.Items.Add(new ToolStripSeparator());

        var exitItem = new ToolStripMenuItem("Salir de Needle");
        exitItem.Click += (_, _) => ExitRequested?.Invoke();
        menu.Items.Add(exitItem);

        _notifyIcon = new NotifyIcon
        {
            Icon = _trayIcon,
            Text = "Needle — Ctrl+Alt+L para bloquear con letras",
            ContextMenuStrip = menu,
            Visible = true
        };
        _notifyIcon.DoubleClick += (_, _) => PreviewRequested?.Invoke();

        RegisterGlobalHotkey();
    }

    public void UpdateStatus(string statusText)
    {
        if (_disposed) return;
        _statusItem.Text = statusText;
    }

    private void RegisterGlobalHotkey()
    {
        var parameters = new HwndSourceParameters("NeedleHotkeySink")
        {
            ParentWindow = new nint(-3), // HWND_MESSAGE
            Width = 0,
            Height = 0
        };
        _hotkeySource = new HwndSource(parameters);
        _hotkeySource.AddHook(WndProc);

        _hotkeyRegistered = NativeMethods.RegisterHotKey(
            _hotkeySource.Handle,
            HotkeyId,
            NativeMethods.MOD_CONTROL | NativeMethods.MOD_ALT | NativeMethods.MOD_NOREPEAT,
            NativeMethods.VK_L);
    }

    private nint WndProc(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_HOTKEY && wParam == HotkeyId)
        {
            handled = true;
            LockWithNeedleRequested?.Invoke();
        }
        return nint.Zero;
    }

    private static Icon CreateSparkleIcon()
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(System.Drawing.Color.Transparent);

            using var bgBrush = new SolidBrush(System.Drawing.Color.FromArgb(255, 22, 32, 58));
            g.FillEllipse(bgBrush, 1, 1, 30, 30);

            using var ringPen = new Pen(System.Drawing.Color.FromArgb(190, 158, 199, 255), 1.5f);
            g.DrawEllipse(ringPen, 2, 2, 28, 28);

            // 4-point star
            var pts = new PointF[8];
            const float cx = 16f, cy = 16f, outer = 10.5f, inner = 2.6f;
            for (int i = 0; i < 8; i++)
            {
                double angle = i * (Math.PI / 4.0) - (Math.PI / 2.0);
                float r = (i % 2 == 0) ? outer : inner;
                pts[i] = new PointF(cx + (float)(Math.Cos(angle) * r), cy + (float)(Math.Sin(angle) * r));
            }
            using var starBrush = new SolidBrush(System.Drawing.Color.White);
            g.FillPolygon(starBrush, pts);
        }

        nint hIcon = bmp.GetHicon();
        try
        {
            using var temp = Icon.FromHandle(hIcon);
            return (Icon)temp.Clone();
        }
        finally
        {
            NativeMethods.DestroyIcon(hIcon);
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (_hotkeySource is not null)
        {
            if (_hotkeyRegistered)
            {
                NativeMethods.UnregisterHotKey(_hotkeySource.Handle, HotkeyId);
                _hotkeyRegistered = false;
            }
            _hotkeySource.RemoveHook(WndProc);
            _hotkeySource.Dispose();
            _hotkeySource = null;
        }

        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _trayIcon.Dispose();
    }
}
