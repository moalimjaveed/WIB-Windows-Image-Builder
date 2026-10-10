using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using WibStudio.Models;

namespace WibStudio.Resources;

public class RiskToBrushConverter : IValueConverter
{
    private static readonly SolidColorBrush LowBrush = new((Color)ColorConverter.ConvertFromString("#16A34A"));
    private static readonly SolidColorBrush MediumBrush = new((Color)ColorConverter.ConvertFromString("#D97706"));
    private static readonly SolidColorBrush HighBrush = new((Color)ColorConverter.ConvertFromString("#DC2626"));
    private static readonly SolidColorBrush DefaultBrush = new((Color)ColorConverter.ConvertFromString("#64748B"));

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is RiskLevel risk)
        {
            return risk switch
            {
                RiskLevel.Low => LowBrush,
                RiskLevel.Medium => MediumBrush,
                RiskLevel.High => HighBrush,
                _ => DefaultBrush
            };
        }
        return DefaultBrush;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class LogLevelToBrushConverter : IValueConverter
{
    private static readonly SolidColorBrush InfoBrush = new((Color)ColorConverter.ConvertFromString("#38BDF8"));
    private static readonly SolidColorBrush SuccessBrush = new((Color)ColorConverter.ConvertFromString("#4ADE80"));
    private static readonly SolidColorBrush WarningBrush = new((Color)ColorConverter.ConvertFromString("#FBBF24"));
    private static readonly SolidColorBrush ErrorBrush = new((Color)ColorConverter.ConvertFromString("#F87171"));
    private static readonly SolidColorBrush DismBrush = new((Color)ColorConverter.ConvertFromString("#C084FC"));
    private static readonly SolidColorBrush StepBrush = new((Color)ColorConverter.ConvertFromString("#F1F5F9"));

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is LogLevel level)
        {
            return level switch
            {
                LogLevel.Info => InfoBrush,
                LogLevel.Success => SuccessBrush,
                LogLevel.Warning => WarningBrush,
                LogLevel.Error => ErrorBrush,
                LogLevel.Dism => DismBrush,
                LogLevel.Step => StepBrush,
                _ => StepBrush
            };
        }
        return StepBrush;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class BooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        bool b = value is true;
        if (parameter is string s && s.Equals("Inverse", StringComparison.OrdinalIgnoreCase))
        {
            b = !b;
        }
        return b ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class LowDiskToBrushConverter : IValueConverter
{
    private static readonly SolidColorBrush NormalBrush = new((Color)ColorConverter.ConvertFromString("#4ADE80"));
    private static readonly SolidColorBrush LowBrush = new((Color)ColorConverter.ConvertFromString("#F59E0B"));

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is true ? LowBrush : NormalBrush;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}
