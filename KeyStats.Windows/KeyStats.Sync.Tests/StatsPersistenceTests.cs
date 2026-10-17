using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization;
using System.Text.Json;
using System.Threading;
using KeyStats.Models;
using KeyStats.Services;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace KeyStats.Sync.Tests;

[TestClass]
public sealed class StatsPersistenceTests
{
    [TestMethod]
    public void AppKeyDistribution_RoundTripsAndClonesWithoutSharingCounts()
    {
        var editor = new AppStats("editor", "Editor");
        editor.RecordKeyPress("Ctrl+C");
        editor.RecordKeyPress("Ctrl+C");
        editor.RecordKeyPress("Space");
        editor.RecordKeyPress();

        var restored = JsonSerializer.Deserialize<AppStats>(JsonSerializer.Serialize(editor));
        Assert.IsNotNull(restored);
        Assert.AreEqual(4, restored!.KeyPresses);
        Assert.AreEqual(2, restored.KeyPressCounts["Ctrl+C"]);
        Assert.AreEqual(1, restored.KeyPressCounts["Space"]);

        var clone = new AppStats(restored);
        clone.KeyPressCounts["Ctrl+C"] = 99;
        Assert.AreEqual(2, restored.KeyPressCounts["Ctrl+C"]);
    }

    [TestMethod]
    public void AppKeyDistribution_LegacyAndNullDataKeepTotalsWithoutInventingKeys()
    {
        foreach (var json in new[] { "{\"KeyPresses\":12}", "{\"KeyPresses\":12,\"KeyPressCounts\":null}" })
        {
            var restored = JsonSerializer.Deserialize<AppStats>(json);
            Assert.IsNotNull(restored);
            Assert.AreEqual(12, restored!.KeyPresses);
            Assert.AreEqual(0, restored.KeyPressCounts.Count);
        }
    }

    [TestMethod]
    public void KeyboardHeatmap_FiltersAppsSortsByKeysAndPreservesSelectionAfterReordering()
    {
        var editor = new AppStats("editor", "Editor");
        editor.RecordKeyPress("Ctrl+C");
        editor.RecordKeyPress("Space");
        var browser = new AppStats("browser", "Browser");
        browser.RecordKeyPress("A");
        var mouseOnly = new AppStats("mouse", "Mouse") { LeftClicks = 1_000 };
        var current = new DailyStats(DateTime.Today)
        {
            KeyPresses = 3,
            KeyPressCounts = new Dictionary<string, int> { ["Ctrl+C"] = 1, ["Space"] = 1, ["A"] = 1 },
            AppStats = new Dictionary<string, AppStats> { ["browser"] = browser, ["mouse"] = mouseOnly, ["editor"] = editor }
        };
        var manager = CreateHeatmapManager(current);

        var all = manager.GetKeyboardHeatmapDay(DateTime.Today);
        Assert.IsNull(all.SelectedAppName);
        Assert.AreEqual(3, all.TotalKeyPresses);
        CollectionAssert.AreEqual(new[] { "editor", "browser" }, all.Apps.Select(app => app.AppName).ToArray());

        var filtered = manager.GetKeyboardHeatmapDay(DateTime.Today, "EDITOR");
        Assert.AreEqual("editor", filtered.SelectedAppName);
        Assert.AreEqual(2, filtered.TotalKeyPresses);
        Assert.AreEqual(1, filtered.KeyCounts["Ctrl"]);
        Assert.AreEqual(1, filtered.KeyCounts["C"]);
        Assert.AreEqual(1, filtered.KeyCounts["Space"]);
        Assert.IsFalse(filtered.KeyCounts.ContainsKey("A"));
        filtered.Apps[0].KeyPressCounts["Space"] = 99;
        Assert.AreEqual(1, editor.KeyPressCounts["Space"]);

        browser.KeyPresses = 20;
        var reordered = manager.GetKeyboardHeatmapDay(DateTime.Today, filtered.SelectedAppName);
        CollectionAssert.AreEqual(new[] { "browser", "editor" }, reordered.Apps.Select(app => app.AppName).ToArray());
        Assert.AreEqual("editor", reordered.SelectedAppName);
        Assert.AreEqual(2, reordered.TotalKeyPresses);
    }

    [TestMethod]
    public void KeyboardHeatmap_HistorySupportsLegacyAppsAndMissingSelectionFallsBackToAll()
    {
        var yesterday = DateTime.Today.AddDays(-1);
        var legacy = new AppStats("legacy", "Legacy") { KeyPresses = 7 };
        var past = new DailyStats(yesterday)
        {
            KeyPresses = 9,
            KeyPressCounts = new Dictionary<string, int> { ["A"] = 9 },
            AppStats = new Dictionary<string, AppStats> { ["legacy"] = legacy }
        };
        var manager = CreateHeatmapManager(new DailyStats(DateTime.Today));
        manager.History[yesterday.ToString("yyyy-MM-dd")] = past;

        var filtered = manager.GetKeyboardHeatmapDay(yesterday, "legacy");
        Assert.AreEqual(7, filtered.TotalKeyPresses);
        Assert.AreEqual(0, filtered.KeyCounts.Count);
        Assert.AreEqual("legacy", filtered.SelectedAppName);

        var missing = manager.GetKeyboardHeatmapDay(yesterday, "missing");
        Assert.IsNull(missing.SelectedAppName);
        Assert.AreEqual(9, missing.TotalKeyPresses);
        Assert.AreEqual(9, missing.KeyCounts["A"]);
        Assert.AreEqual(0, manager.GetKeyboardHeatmapDay(DateTime.Today).Apps.Count);
    }

    [TestMethod]
    public void AppKeyDistribution_ImportMergeNormalizesAndCombinesCounts()
    {
        var existing = new DailyStats(DateTime.Today);
        existing.AppStats["editor"] = new AppStats("editor")
        {
            KeyPresses = 3,
            KeyPressCounts = new Dictionary<string, int> { ["A"] = 2, ["Ctrl+C"] = 1 }
        };
        var incoming = new DailyStats(DateTime.Today);
        incoming.AppStats["editor"] = new AppStats("editor")
        {
            KeyPresses = 4,
            KeyPressCounts = new Dictionary<string, int> { [" A "] = 3, ["Ctrl+C"] = 1, ["B"] = -1, [" "] = 8 }
        };
        var merge = typeof(StatsManager).GetMethod("MergeDailyStats", BindingFlags.Static | BindingFlags.NonPublic);
        Assert.IsNotNull(merge);
        var result = (DailyStats)merge!.Invoke(null, new object[] { existing, incoming })!;

        Assert.AreEqual(7, result.AppStats["editor"].KeyPresses);
        Assert.AreEqual(5, result.AppStats["editor"].KeyPressCounts["A"]);
        Assert.AreEqual(2, result.AppStats["editor"].KeyPressCounts["Ctrl+C"]);
        Assert.AreEqual(2, result.AppStats["editor"].KeyPressCounts.Count);
        Assert.AreEqual(2, existing.AppStats["editor"].KeyPressCounts["A"]);
    }

    private static StatsManager CreateHeatmapManager(DailyStats current)
    {
        var manager = (StatsManager)FormatterServices.GetUninitializedObject(typeof(StatsManager));
        SetField(manager, "_lock", new object());
        SetField(manager, "<CurrentStats>k__BackingField", current);
        SetField(manager, "<History>k__BackingField", new Dictionary<string, DailyStats>());
        return manager;
    }

    [TestMethod]
    public void ContinuousActivity_SavesBeforeInputStops()
    {
        TestPlatform.RequireWindows();
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "daily_stats.json");
        var manager = (StatsManager)FormatterServices.GetUninitializedObject(typeof(StatsManager));
        var stateLock = new object();
        SetField(manager, "_lock", stateLock);
        SetField(manager, "_statsFilePath", path);
        SetField(manager, "_saveInterval", 200.0);
        SetField(manager, "<CurrentStats>k__BackingField", new DailyStats(DateTime.Today) { KeyPresses = 42 });
        SetField(manager, "<History>k__BackingField", new Dictionary<string, DailyStats>());
        var scheduleSave = typeof(StatsManager).GetMethod("ScheduleSave", BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.IsNotNull(scheduleSave);

        try
        {
            var elapsed = Stopwatch.StartNew();
            while (!File.Exists(path) && elapsed.Elapsed < TimeSpan.FromSeconds(5))
            {
                scheduleSave!.Invoke(manager, null);
                Thread.Sleep(10);
            }

            Assert.IsTrue(File.Exists(path), "Continuous events must not postpone the first save until idle.");
            lock (stateLock)
            {
                var saved = JsonSerializer.Deserialize<DailyStats>(File.ReadAllText(path));
                Assert.IsNotNull(saved);
                Assert.AreEqual(42, saved!.KeyPresses);
            }
        }
        finally
        {
            lock (stateLock)
            {
                SetField(manager, "_isDisposed", true);
                SetField(manager, "_pendingSave", false);
                var timer = typeof(StatsManager).GetField("_saveTimer", BindingFlags.Instance | BindingFlags.NonPublic)
                    ?.GetValue(manager) as System.Timers.Timer;
                timer?.Dispose();
            }
        }
    }

    private static void SetField(object target, string name, object value)
    {
        var field = target.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.IsNotNull(field, "Missing test setup field: " + name);
        field!.SetValue(target, value);
    }
}
