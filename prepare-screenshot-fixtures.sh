#!/usr/bin/env bash

set -euo pipefail

ROOT="${FIXTURE_ROOT:-${HOME}/TabflowScreenshot/Fixtures}"

if [[ -z "$ROOT" || "$ROOT" == "/" || "$ROOT" == "$HOME" ]]; then
    echo "Refusing to replace unsafe fixture root: ${ROOT:-<empty>}" >&2
    exit 2
fi

rm -rf "$ROOT"

mkdir -p \
    "$ROOT/Project" \
    "$ROOT/Data" \
    "$ROOT/Web" \
    "$ROOT/Design" \
    "$ROOT/Documents"

cat > "$ROOT/Design/AppIcon.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="400" viewBox="0 0 640 400">
  <rect width="640" height="400" rx="32" fill="#f5f5f7"/>
  <rect x="80" y="72" width="480" height="256" rx="24" fill="#ffffff" stroke="#d2d2d7" stroke-width="4"/>
  <rect x="112" y="112" width="176" height="112" rx="16" fill="#e8e8ed"/>
  <rect x="312" y="112" width="216" height="20" rx="10" fill="#d2d2d7"/>
  <rect x="312" y="152" width="168" height="16" rx="8" fill="#e8e8ed"/>
  <rect x="112" y="256" width="416" height="16" rx="8" fill="#e8e8ed"/>
</svg>
EOF

# ============================================================
# README.md
# ============================================================

cat > "$ROOT/Project/README.md" <<'EOF'
# Harbor

A workspace for planning, reporting, and review.

Harbor keeps project notes, metrics, and design files in one place so the
team can move between documents without losing context.

## Overview

The workspace is organized around three ideas:

1. Clear project structure
2. Shared metrics
3. Lightweight review

## Contents

- README.md
- ContentView.swift
- Release Notes.txt
- status.txt

## Status

Current focus:

- Dashboard layout
- Quarterly metrics
- Design review
- Localization samples
EOF


# ============================================================
# ContentView.swift
# ============================================================

cat > "$ROOT/Project/ContentView.swift" <<'EOF'
import SwiftUI

struct ContentView: View {
    @State private var selectedMode: SwitcherMode = .recent
    @State private var showPreviews = true
    @State private var includeMinimized = true

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            dashboard
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    private var sidebar: some View {
        List {
            Section("Workspace") {
                Label("Overview", systemImage: "rectangle.grid.2x2")
                Label("Windows", systemImage: "macwindow.on.rectangle")
                Label("Shortcuts", systemImage: "keyboard")
            }

            Section("Configuration") {
                Label("Appearance", systemImage: "paintbrush")
                Label("Permissions", systemImage: "lock.shield")
                Label("Advanced", systemImage: "gearshape.2")
            }
        }
        .navigationTitle("Harbor")
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                summaryCards
                switcherPreview
                preferences
            }
            .padding(32)
        }
        .navigationTitle("Overview")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workspace Overview")
                .font(.system(size: 34, weight: .bold))

            Text("Review metrics, documents, and design progress in one place.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 16) {
            metricCard(
                title: "Open Windows",
                value: "12",
                systemImage: "macwindow"
            )

            metricCard(
                title: "Applications",
                value: "7",
                systemImage: "square.grid.2x2"
            )

            metricCard(
                title: "Displays",
                value: "2",
                systemImage: "display.2"
            )
        }
    }

    private func metricCard(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 30, weight: .semibold))

            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var switcherPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Files")
                .font(.headline)

            HStack(spacing: 14) {
                previewWindow(
                    title: "Dashboard",
                    app: "Safari",
                    selected: false
                )

                previewWindow(
                    title: "ContentView.swift",
                    app: "Xcode",
                    selected: true
                )

                previewWindow(
                    title: "Project",
                    app: "Finder",
                    selected: false
                )
            }
        }
    }

    private func previewWindow(
        title: String,
        app: String,
        selected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(height: 110)
                .overlay {
                    Image(systemName: "macwindow")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }

            Text(title)
                .font(.headline)
                .lineLimit(1)

            Text(app)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    selected ? Color.accentColor : Color.secondary.opacity(0.2),
                    lineWidth: selected ? 3 : 1
                )
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.headline)

            Picker("Window ordering", selection: $selectedMode) {
                ForEach(SwitcherMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }

            Toggle("Show window previews", isOn: $showPreviews)

            Toggle(
                "Include minimized windows",
                isOn: $includeMinimized
            )
        }
        .padding(20)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private enum SwitcherMode: String, CaseIterable, Identifiable {
    case recent
    case application
    case display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recently Used"
        case .application:
            return "By Application"
        case .display:
            return "By Display"
        }
    }
}

#Preview {
    ContentView()
}
EOF


# ============================================================
# Release Notes.txt
# ============================================================

cat > "$ROOT/Project/Release Notes.txt" <<'EOF'
HARBOR 1.0
Release Notes

Harbor 1.0 collects the workspace documents used for planning and review.

WHAT'S NEW

Shared dashboard

Monthly visitors, sessions, and conversion are collected in one spreadsheet.

Project brief

The brief describes goals, timeline, and review criteria for the current
cycle.

Design sample

The icon draft is stored as a local SVG so review does not depend on a
network.

NEXT

- Finalize quarterly charts
- Review the dashboard layout
- Publish the workspace snapshot
EOF


# ============================================================
# Dashboard.csv
# ============================================================

cat > "$ROOT/Data/Dashboard.csv" <<'EOF'
Month,Visitors,Sessions,Page Views,Avg Session Minutes,Conversion Rate
January,1280,4320,18420,24.8,2.4
February,1460,4810,21560,26.4,2.6
March,1710,5350,26430,27.1,2.8
April,1950,6010,31880,28.9,3.1
May,2240,6840,39120,30.2,3.3
June,2510,7420,45170,31.6,3.5
July,2870,8210,52340,32.4,3.6
August,3190,8960,59680,33.2,3.8
September,3540,9780,67840,34.1,4.0
October,3980,10840,76290,35.5,4.1
November,4370,11720,84310,36.1,4.3
December,4810,12860,93840,37.3,4.5
EOF


# ============================================================
# Dashboard.html
# ============================================================

cat > "$ROOT/Web/Dashboard.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">

<title>Dashboard</title>

<style>
:root {
    color-scheme: light;
    font-family:
        -apple-system,
        BlinkMacSystemFont,
        "SF Pro Display",
        "SF Pro Text",
        sans-serif;

    background: #f5f5f7;
    color: #1d1d1f;
}

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    min-height: 100vh;
    background:
        radial-gradient(circle at 8% 0%, #ffd7b3 0%, transparent 34%),
        radial-gradient(circle at 92% 8%, #c7d2fe 0%, transparent 32%),
        radial-gradient(circle at 78% 88%, #bbf7d0 0%, transparent 30%),
        #f8fafc;
}

.page {
    width: min(1160px, calc(100% - 64px));
    margin: 0 auto;
    padding: 64px 0 100px;
}

.nav {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 54px;
}

.brand {
    font-size: 18px;
    font-weight: 650;
    color: #4f46e5;
}

.nav-items {
    display: flex;
    gap: 28px;
    color: #6e6e73;
    font-size: 14px;
}

.hero {
    display: flex;
    justify-content: space-between;
    align-items: end;
    gap: 60px;
    margin-bottom: 40px;
}

.hero h1 {
    margin: 0;
    font-size: 52px;
    line-height: 1;
    letter-spacing: -1.7px;
}

.hero p {
    max-width: 510px;
    margin: 16px 0 0;
    color: #6e6e73;
    font-size: 19px;
    line-height: 1.5;
}

.period {
    padding: 9px 14px;
    background: white;
    border: 1px solid #dedee3;
    border-radius: 10px;
    color: #515154;
    font-size: 14px;
    white-space: nowrap;
}

.metrics {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 18px;
    margin-bottom: 18px;
}

.card {
    background: white;
    border: 1px solid rgba(0,0,0,.055);
    border-radius: 20px;
    padding: 24px;
    box-shadow: 0 8px 28px rgba(0,0,0,.045);
}

.metrics .card:nth-child(1) .metric-value { color: #ea580c; }
.metrics .card:nth-child(2) .metric-value { color: #4f46e5; }
.metrics .card:nth-child(3) .metric-value { color: #0891b2; }
.metrics .card:nth-child(4) .metric-value { color: #16a34a; }

.metric-label {
    color: #86868b;
    font-size: 14px;
    margin-bottom: 12px;
}

.metric-value {
    font-size: 34px;
    font-weight: 680;
    letter-spacing: -1px;
}

.metric-change {
    margin-top: 10px;
    color: #3b7a57;
    font-size: 13px;
}

.main-grid {
    display: grid;
    grid-template-columns: 2fr 1fr;
    gap: 18px;
}

.chart-card {
    min-height: 380px;
}

.card-title {
    font-size: 17px;
    font-weight: 650;
}

.card-subtitle {
    margin-top: 5px;
    color: #86868b;
    font-size: 13px;
}

.chart {
    height: 240px;
    margin-top: 28px;
    position: relative;
    display: flex;
    align-items: end;
    gap: 14px;
    padding: 0 8px 26px;
    border-bottom: 1px solid #dedee3;
}

.chart::before,
.chart::after {
    content: "";
    position: absolute;
    left: 0;
    right: 0;
    border-top: 1px dashed #e5e5ea;
}

.chart::before {
    top: 65px;
}

.chart::after {
    top: 135px;
}

.bar {
    flex: 1;
    min-width: 20px;
    background: linear-gradient(180deg, #6366f1 0%, #22d3ee 100%);
    border-radius: 6px 6px 2px 2px;
    position: relative;
    z-index: 2;
}

.bar span {
    position: absolute;
    top: calc(100% + 9px);
    left: 50%;
    transform: translateX(-50%);
    color: #86868b;
    font-size: 11px;
}

.activity {
    margin-top: 20px;
}

.activity-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 15px 0;
    border-bottom: 1px solid #ededf0;
}

.activity-item:last-child {
    border-bottom: 0;
}

.activity-main {
    min-width: 0;
}

.activity-title {
    font-size: 14px;
    font-weight: 580;
}

.activity-meta {
    margin-top: 4px;
    color: #86868b;
    font-size: 12px;
}

.activity-value {
    font-size: 13px;
    color: #515154;
}

.footer-note {
    margin-top: 22px;
    color: #86868b;
    font-size: 12px;
}
</style>
</head>

<body>

<div class="page">

    <div class="nav">
        <div class="brand">Harbor Analytics</div>

        <div class="nav-items">
            <span>Overview</span>
            <span>Activity</span>
            <span>Reports</span>
            <span>Settings</span>
        </div>
    </div>

    <div class="hero">
        <div>
            <h1>Dashboard</h1>
            <p>
                Monthly visitors, sessions, and conversion across the
                Harbor workspace.
            </p>
        </div>

        <div class="period">
            Last 30 days
        </div>
    </div>

    <section class="metrics">

        <div class="card">
            <div class="metric-label">Active users</div>
            <div class="metric-value">3,190</div>
            <div class="metric-change">↑ 11.1% this month</div>
        </div>

        <div class="card">
            <div class="metric-label">Sessions</div>
            <div class="metric-value">8,960</div>
            <div class="metric-change">↑ 9.1% this month</div>
        </div>

        <div class="card">
            <div class="metric-label">Page views</div>
            <div class="metric-value">59.7K</div>
            <div class="metric-change">↑ 14.0% this month</div>
        </div>

        <div class="card">
            <div class="metric-label">Conversion</div>
            <div class="metric-value">3.8%</div>
            <div class="metric-change">↑ 0.4 points</div>
        </div>

    </section>

    <section class="main-grid">

        <div class="card chart-card">
            <div class="card-title">Visitor activity</div>
            <div class="card-subtitle">
                Sessions during the last twelve months
            </div>

            <div class="chart">
                <div class="bar" style="height: 22%"><span>Jan</span></div>
                <div class="bar" style="height: 27%"><span>Feb</span></div>
                <div class="bar" style="height: 33%"><span>Mar</span></div>
                <div class="bar" style="height: 40%"><span>Apr</span></div>
                <div class="bar" style="height: 48%"><span>May</span></div>
                <div class="bar" style="height: 56%"><span>Jun</span></div>
                <div class="bar" style="height: 64%"><span>Jul</span></div>
                <div class="bar" style="height: 72%"><span>Aug</span></div>
                <div class="bar" style="height: 80%"><span>Sep</span></div>
                <div class="bar" style="height: 88%"><span>Oct</span></div>
                <div class="bar" style="height: 94%"><span>Nov</span></div>
                <div class="bar" style="height: 100%"><span>Dec</span></div>
            </div>

            <div class="footer-note">
                Activity is generated locally for the screenshot fixture.
            </div>
        </div>

        <div class="card">
            <div class="card-title">Recent activity</div>
            <div class="card-subtitle">
                Latest workspace events
            </div>

            <div class="activity">

                <div class="activity-item">
                    <div class="activity-main">
                        <div class="activity-title">
                            Dashboard published
                        </div>
                        <div class="activity-meta">
                            Harbor Analytics
                        </div>
                    </div>
                    <div class="activity-value">2m</div>
                </div>

                <div class="activity-item">
                    <div class="activity-main">
                        <div class="activity-title">
                            Metrics spreadsheet updated
                        </div>
                        <div class="activity-meta">
                            December figures
                        </div>
                    </div>
                    <div class="activity-value">12m</div>
                </div>

                <div class="activity-item">
                    <div class="activity-main">
                        <div class="activity-title">
                            Project brief reviewed
                        </div>
                        <div class="activity-meta">
                            Design cycle
                        </div>
                    </div>
                    <div class="activity-value">1h</div>
                </div>

                <div class="activity-item">
                    <div class="activity-main">
                        <div class="activity-title">
                            Icon draft uploaded
                        </div>
                        <div class="activity-meta">
                            AppIcon.svg
                        </div>
                    </div>
                    <div class="activity-value">3h</div>
                </div>

                <div class="activity-item">
                    <div class="activity-main">
                        <div class="activity-title">
                            Workspace snapshot saved
                        </div>
                        <div class="activity-meta">
                            Local files only
                        </div>
                    </div>
                    <div class="activity-value">Today</div>
                </div>

            </div>
        </div>

    </section>

</div>

</body>
</html>
EOF


# ============================================================
# Project Brief.rtf
# ============================================================

cat > "$ROOT/Documents/Project Brief.rtf" <<'EOF'
{\rtf1\ansi\deff0
{\fonttbl
{\f0 Helvetica;}
{\f1 Helvetica-Bold;}
}

\f1\fs48 Harbor Project Brief\f0\fs24\par
\par

\f1 Overview\f0\par
\par
Harbor is a shared workspace for planning, metrics, and design review.
The team keeps briefs, spreadsheets, and visual drafts together so weekly
reviews stay in one place.\par
\par

\f1 Product Goal\f0\par
\par
Give the team a stable set of documents for dashboard layout, conversion
tracking, and design checkpoints.\par
\par

\f1 Key Deliverables\f0\par
\par
- Analytics dashboard\par
- Monthly metrics spreadsheet\par
- Project brief\par
- Icon draft\par
- Release notes\par
\par

\f1 Design Principles\f0\par
\par
Clarity\par
Charts and labels should be readable at a glance.\par
\par

Speed\par
Documents should open locally without network dependencies.\par
\par

Stability\par
File names and window titles stay the same across review cycles.\par
\par

\f1 Success Criteria\f0\par
\par
- Dashboard shows current month metrics\par
- Spreadsheet matches the published charts\par
- Brief describes the next review cycle\par
- Design draft is stored as a local SVG\par
\par

\f1 Tagline\f0\par
\par
Harbor\par
Plan, measure, review.\par
}
EOF


# ============================================================
# Terminal 示例辅助文件
# ============================================================

cat > "$ROOT/Project/status.txt" <<'EOF'
HARBOR WORKSPACE STATUS

Build
-----
Configuration       Release
Architecture        Apple Silicon / Intel
Localization        English / Simplified Chinese

Documents
---------
Dashboard.html              Ready
Dashboard.csv               Ready
Project Brief.rtf           Ready
AppIcon.svg                 Ready

Current Focus
-------------
- Quarterly metrics
- Dashboard layout
- Design review
- Localization samples
EOF


chmod -R a+rX "$ROOT"

echo
echo "Tabflow screenshot fixtures prepared:"
echo "$ROOT"
echo
echo "Files:"
find "$ROOT" -maxdepth 2 -type f | sort
