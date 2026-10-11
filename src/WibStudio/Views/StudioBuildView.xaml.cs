using System.Collections.Specialized;
using System.Windows.Controls;
using WibStudio.ViewModels;

namespace WibStudio.Views;

public partial class StudioBuildView : UserControl
{
    public StudioBuildView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, System.Windows.DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is StudioBuildViewModel vm)
        {
            vm.LogEntries.CollectionChanged += OnLogEntriesChanged;
        }
    }

    private void OnLogEntriesChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        Dispatcher.InvokeAsync(() =>
        {
            ConsoleScrollViewer.ScrollToEnd();
        }, System.Windows.Threading.DispatcherPriority.Background);
    }
}
