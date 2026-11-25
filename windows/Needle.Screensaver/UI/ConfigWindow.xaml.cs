using System.Windows;

namespace Needle.Screensaver.UI;

public partial class ConfigWindow : Window
{
    public event Action? PreviewRequested;

    public ConfigWindow()
    {
        InitializeComponent();
    }

    private void OnPreviewClick(object sender, RoutedEventArgs e)
    {
        PreviewRequested?.Invoke();
    }

    private void OnCloseClick(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
