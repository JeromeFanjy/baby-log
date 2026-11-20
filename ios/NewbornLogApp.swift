// NewbornLogApp.swift
// 宝宝记录 —— 新生儿喂养 / 尿布 / 补剂记录（SwiftUI，iOS 15+）
//
// 使用方法：
//   1. Xcode 新建 iOS App 项目（Interface: SwiftUI，名称随意，如 BabyLog）
//   2. 删除模板自带的 BabyLogApp.swift 和 ContentView.swift（两个都删）
//   3. 把本文件拖进项目，勾选 Target Membership（你的 App target）
//   4. 选择自己的签名 Team，连接 iPhone，Run 即可安装
//
// 数据保存在手机本机（UserDefaults）。支持导出/导入 JSON 备份。

import SwiftUI
import UIKit

// MARK: - 模型

enum RecordKind: String, Codable, CaseIterable {
    case feed, diaper, supp

    var title: String {
        switch self {
        case .feed: return "喂养"
        case .diaper: return "尿布"
        case .supp: return "补剂"
        }
    }
    var icon: String {
        switch self {
        case .feed: return "🍼"
        case .diaper: return "🧷"
        case .supp: return "💊"
        }
    }
    var color: Color {
        switch self {
        case .feed: return Color(red: 0.949, green: 0.60, blue: 0.29)
        case .diaper: return Color(red: 0.306, green: 0.62, blue: 0.83)
        case .supp: return Color(red: 0.31, green: 0.686, blue: 0.553)
        }
    }
}

struct Record: Identifiable, Codable {
    var id = UUID()
    var kind: RecordKind
    var time: Date
    var note: String = ""

    // 喂养
    var feedMode: String = "bf"      // bf = 亲喂, stored = 储存奶, formula = 配方奶
    var side: String = ""            // left / right / both
    var minutes: Int = 0
    var ml: Int = 0
    var storedState: String = ""     // 储存奶状态：冷冻 / 冷藏 / 常温 / 现挤

    // 尿布
    var diaperKind: String = "pee"   // pee / poop / both
    var amount: String = ""
    var consistency: String = ""
    var color: String = ""

    // 补剂
    var suppName: String = ""
    var dose: String = ""

    var summary: String {
        switch kind {
        case .feed:
            if feedMode == "bf" {
                var parts = ["母乳亲喂"]
                if side == "left" { parts.append("左侧") }
                else if side == "right" { parts.append("右侧") }
                else if side == "both" { parts.append("双侧") }
                if minutes > 0 { parts.append(Self.minText(minutes)) }
                return parts.joined(separator: " · ")
            }
            var s = feedMode == "stored" ? "储存奶" : (feedMode == "formula" ? "配方奶" : "瓶喂")
            if ml > 0 { s += " · \(ml) ml" }
            if feedMode == "stored", !storedState.isEmpty { s += " · \(storedState)" }
            return s
        case .diaper:
            let kindText = ["pee": "小便", "poop": "大便", "both": "小便+大便"][diaperKind] ?? "尿布"
            var bits = [kindText]
            if diaperKind != "pee" {
                if !consistency.isEmpty { bits.append(consistency) }
                if !color.isEmpty { bits.append(color) }
            }
            if !amount.isEmpty { bits.append(amount) }
            return bits.joined(separator: " · ")
        case .supp:
            let name = suppName.isEmpty ? "补剂" : suppName
            return dose.isEmpty ? name : "\(name) · \(dose)"
        }
    }

    static func minText(_ m: Int) -> String {
        if m >= 60 {
            let h = m / 60, r = m % 60
            return r == 0 ? "\(h)小时" : "\(h)小时\(r)分"
        }
        return "\(m)分钟"
    }
}

struct Stats {
    var feedCount = 0, bfMinutes = 0, storedMl = 0, formulaMl = 0
    var peeCount = 0, poopCount = 0, diaperCount = 0
    var suppCount = 0
}

// MARK: - 数据仓库

final class Store: ObservableObject {
    @Published var records: [Record] = [] {
        didSet { save() }
    }
    private let key = "babyLog.records.v1"

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              var r = try? JSONDecoder().decode([Record].self, from: data) else { return }
        // 旧版本数据迁移：早期「瓶喂」(bottle) 归入「配方奶」
        for i in r.indices where r[i].feedMode == "bottle" {
            r[i].feedMode = "formula"
        }
        records = r.sorted { $0.time > $1.time }
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func upsert(_ r: Record) {
        if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r }
        else { records.append(r) }
        records.sort { $0.time > $1.time }
    }
    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
    }
    func clearAll() {
        records = []
    }

    func stats(on day: Date) -> Stats {
        var s = Stats()
        let cal = Calendar.current
        for r in records where cal.isDate(r.time, inSameDayAs: day) {
            switch r.kind {
            case .feed:
                s.feedCount += 1
                if r.feedMode == "bf" { s.bfMinutes += r.minutes }
                else if r.feedMode == "stored" { s.storedMl += r.ml }
                else { s.formulaMl += r.ml }
            case .diaper:
                s.diaperCount += 1
                if r.diaperKind == "pee" { s.peeCount += 1 }
                else if r.diaperKind == "poop" { s.poopCount += 1 }
                else { s.peeCount += 1; s.poopCount += 1 }
            case .supp:
                s.suppCount += 1
            }
        }
        return s
    }

    // MARK: 导出 / 导入
    func exportJSON() -> String {
        struct Envelope: Codable {
            var app = "宝宝记录"
            var version = 1
            var exportedAt = Date()
            var records: [Record]
        }
        let env = Envelope(records: records)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(env) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    @discardableResult
    func importJSON(_ text: String) -> Int {
        struct Envelope: Codable {
            var records: [Record]
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var incoming: [Record]?
        if let data = text.data(using: .utf8),
           let env = try? dec.decode(Envelope.self, from: data) {
            incoming = env.records
        } else if let data = text.data(using: .utf8),
                  let bare = try? dec.decode([Record].self, from: data) {
            incoming = bare
        }
        guard let list = incoming, !list.isEmpty else { return 0 }
        var map: [UUID: Record] = [:]
        for r in records { map[r.id] = r }
        for r in list { map[r.id] = r }
        records = Array(map.values).sorted { $0.time > $1.time }
        return list.count
    }
}

// MARK: - 日期工具

enum DayUtil {
    static func startOfDay(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }
    static func shift(_ d: Date, by days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: d) ?? d
    }
    static func label(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        if cal.isDate(d, inSameDayAs: shift(Date(), by: -2)) { return "前天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }
    static func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: d)
    }
    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 主界面

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var selectedDay = Date()
    @State private var activeSheet: ActiveSheet?
    @State private var showSettings = false

    enum ActiveSheet: Identifiable {
        case add(RecordKind)
        case edit(Record)
        var id: String {
            switch self {
            case .add(let k): return "add-\(k.rawValue)"
            case .edit(let r): return "edit-\(r.id.uuidString)"
            }
        }
    }

    private var dayRecords: [Record] {
        store.records.filter { Calendar.current.isDate($0.time, inSameDayAs: selectedDay) }
    }
    private var stats: Stats { store.stats(on: selectedDay) }

    var body: some View {
        VStack(spacing: 0) {
            header
            dateNav
            statsRow
            timelineList
        }
        .background(Color(red: 0.965, green: 0.957, blue: 0.937).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { addBar }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add(let kind):
                RecordFormView(kind: kind, existing: nil)
                    .environmentObject(store)
            case .edit(let record):
                RecordFormView(kind: record.kind, existing: record)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
    }

    private var header: some View {
        HStack {
            Text("👶 宝宝记录").font(.system(size: 20, weight: .bold))
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 42, height: 42)
                    .background(Color.white, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var dateNav: some View {
        HStack {
            Button { selectedDay = DayUtil.shift(selectedDay, by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            }
            Spacer()
            VStack(spacing: 1) {
                Text(DayUtil.label(selectedDay)).font(.system(size: 19, weight: .bold))
                Text("\(DayUtil.weekday(selectedDay)) · \(dateText(selectedDay))")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                selectedDay = DayUtil.shift(selectedDay, by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(Calendar.current.isDateInToday(selectedDay))
            .opacity(Calendar.current.isDateInToday(selectedDay) ? 0.25 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatCard(icon: "🍼", accent: RecordKind.feed.color,
                     big: "\(stats.feedCount)", unit: "次",
                     sub: feedSub)
            StatCard(icon: "🧷", accent: RecordKind.diaper.color,
                     big: "尿 \(stats.peeCount) · 便 \(stats.poopCount)", unit: "",
                     sub: stats.diaperCount > 0 ? "共换 \(stats.diaperCount) 次" : "暂无记录")
            StatCard(icon: "💊", accent: RecordKind.supp.color,
                     big: "\(stats.suppCount)", unit: "项",
                     sub: stats.suppCount > 0 ? "已按时补充" : "暂无记录")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var feedSub: String {
        var parts: [String] = []
        if stats.bfMinutes > 0 { parts.append("亲喂 \(Record.minText(stats.bfMinutes))") }
        if stats.storedMl > 0 { parts.append("储奶 \(stats.storedMl) ml") }
        if stats.formulaMl > 0 { parts.append("配方 \(stats.formulaMl) ml") }
        return parts.isEmpty ? (stats.feedCount > 0 ? "" : "暂无记录") : parts.joined(separator: " · ")
    }

    private var timelineList: some View {
        Group {
            if dayRecords.isEmpty {
                VStack(spacing: 8) {
                    Text("🌙").font(.system(size: 42))
                    Text("这一天还没有记录\n点下方按钮开始记录吧")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(dayRecords) { r in
                            Button { activeSheet = .edit(r) } label: {
                                RecordRow(r)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("全天 \(dayRecords.count) 条记录")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: 10) {
            AddButton("🍼 喂养", RecordKind.feed.color) { activeSheet = .add(.feed) }
            AddButton("🧷 尿布", RecordKind.diaper.color) { activeSheet = .add(.diaper) }
            AddButton("💊 补剂", RecordKind.supp.color) { activeSheet = .add(.supp) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct StatCard: View {
    let icon: String
    let accent: Color
    let big: String
    let unit: String
    let sub: String

    var body: some View {
        VStack(spacing: 3) {
            Text(icon).font(.system(size: 22))
            Text(big).font(.system(size: 21, weight: .heavy))
                + Text(unit).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.secondary)
            Text(sub)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .padding(.horizontal, 6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottom) {
            Rectangle().fill(accent).frame(height: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct RecordRow: View {
    let record: Record
    var body: some View {
        HStack(spacing: 12) {
            Text(record.kind.icon).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(recordTitle).font(.system(size: 15.5, weight: .bold))
                Text(record.summary)
                    .font(.system(size: 13.5))
                    .foregroundColor(.secondary)
                if !record.note.isEmpty {
                    Text("💬 \(record.note)")
                        .font(.system(size: 13.5))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(DayUtil.clock(record.time))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var recordTitle: String {
        switch record.kind {
        case .feed:
            if record.feedMode == "bf" { return "母乳亲喂" }
            if record.feedMode == "stored" { return "储存奶" }
            return "配方奶"
        case .diaper:
            return ["pee": "小便", "poop": "大便", "both": "小便+大便"][record.diaperKind] ?? "尿布"
        case .supp: return record.suppName.isEmpty ? "补剂" : record.suppName
        }
    }
}

struct AddButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    init(_ label: String, _ color: Color, action: @escaping () -> Void) {
        self.label = label
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(color, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - 记录表单

final class BFClock: ObservableObject {
    @Published var running = false
    @Published var seconds = 0
    private var startDate: Date?
    private var timer: Timer?

    var used: Bool { running || seconds > 0 }

    func toggle() {
        if running { stop() } else { start() }
    }
    private func start() {
        running = true
        startDate = Date()
        seconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let s = self.startDate else { return }
            self.seconds = Int(Date().timeIntervalSince(s))
        }
    }
    private func stop() {
        running = false
        timer?.invalidate()
        timer = nil
    }
}

struct RecordFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let kind: RecordKind
    let existing: Record?

    @State private var time: Date
    @State private var note: String

    @State private var feedMode: String
    @State private var side: String
    @State private var minutes: Int
    @State private var ml: Int
    @State private var storedState: String
    @StateObject private var clock = BFClock()

    @State private var diaperKind: String
    @State private var amount: String
    @State private var consistency: String
    @State private var color: String

    @State private var suppName: String
    @State private var dose: String

    @State private var showValidation = false
    @State private var validationText = ""
    @State private var showDeleteConfirm = false

    init(kind: RecordKind, existing: Record?) {
        self.kind = kind
        self.existing = existing
        let r = existing ?? Record(kind: kind, time: Date())
        _time = State(initialValue: r.time)
        _note = State(initialValue: r.note)
        _feedMode = State(initialValue: r.feedMode)
        _side = State(initialValue: r.side)
        _minutes = State(initialValue: r.minutes)
        _ml = State(initialValue: r.ml)
        _storedState = State(initialValue: r.storedState)
        _diaperKind = State(initialValue: r.diaperKind)
        _amount = State(initialValue: r.amount)
        _consistency = State(initialValue: r.consistency)
        _color = State(initialValue: r.color)
        _suppName = State(initialValue: r.suppName)
        _dose = State(initialValue: r.dose)
    }

    var body: some View {
        NavigationView {
            Form {
                switch kind {
                case .feed: feedSection
                case .diaper: diaperSection
                case .supp: suppSection
                }
                Section("时间") {
                    DatePicker("记录时间", selection: $time)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }
                Section("备注（可选）") {
                    TextField("例如：吐奶较多 / 换了新奶粉", text: $note)
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("删除这条记录")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(existing == nil ? "新增" : "编辑")\(kind.title)记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .tint(kind.color)
        }
        .alert("提示", isPresented: $showValidation) {
            Button("好", role: .cancel) {}
        } message: {
            Text(validationText)
        }
        .confirmationDialog("确定删除这条记录吗？删除后无法恢复。", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let e = existing {
                    store.delete(e.id)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onDisappear { clock.stop() }
    }

    // MARK: 各类型表单

    @ViewBuilder
    private var feedSection: some View {
        Section("喂养方式") {
            Picker("喂养方式", selection: $feedMode) {
                Text("母乳亲喂").tag("bf")
                Text("储存奶").tag("stored")
                Text("配方奶").tag("formula")
            }
            .pickerStyle(.segmented)
        }
        if feedMode == "bf" {
            Section("哺乳侧") {
                Picker("哺乳侧", selection: $side) {
                    Text("未选择").tag("")
                    Text("左侧").tag("left")
                    Text("右侧").tag("right")
                    Text("双侧").tag("both")
                }
                .pickerStyle(.segmented)
            }
            Section("时长（分钟）") {
                HStack {
                    TextField("亲喂时长", value: $minutes, format: .number)
                        .keyboardType(.numberPad)
                    Button(clock.running ? "停止计时" : "开始计时") {
                        clock.toggle()
                        if !clock.running, clock.seconds > 0 {
                            minutes = max(1, Int(ceil(Double(clock.seconds) / 60.0)))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(kind.color)
                }
                if clock.running || clock.seconds > 0 {
                    HStack {
                        Spacer()
                        Text("⏱ \(clockText)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(kind.color)
                            .monospacedDigit()
                        Spacer()
                    }
                }
            }
        } else if feedMode == "stored" {
            Section("奶量（ml）") {
                TextField("例如 90", value: $ml, format: .number)
                    .keyboardType(.numberPad)
            }
            Section("状态（可选）") {
                Picker("状态", selection: $storedState) {
                    Text("未选择").tag("")
                    Text("冷冻").tag("冷冻")
                    Text("冷藏").tag("冷藏")
                    Text("常温").tag("常温")
                    Text("现挤").tag("现挤")
                }
                .pickerStyle(.menu)
            }
        } else {
            Section("奶量（ml）") {
                TextField("例如 90", value: $ml, format: .number)
                    .keyboardType(.numberPad)
            }
        }
    }

    private var clockText: String {
        String(format: "%02d:%02d", clock.seconds / 60, clock.seconds % 60)
    }

    @ViewBuilder
    private var diaperSection: some View {
        Section("类型") {
            Picker("类型", selection: $diaperKind) {
                Text("小便").tag("pee")
                Text("大便").tag("poop")
                Text("都有").tag("both")
            }
            .pickerStyle(.segmented)
        }
        if diaperKind != "pee" {
            Section("大便性状") {
                Picker("大便性状", selection: $consistency) {
                    Text("未选择").tag("")
                    Text("正常").tag("正常")
                    Text("稀水").tag("稀水")
                    Text("干硬").tag("干硬")
                }
                .pickerStyle(.segmented)
            }
            Section("大便颜色") {
                Picker("大便颜色", selection: $color) {
                    Text("未选择").tag("")
                    Text("黄").tag("黄")
                    Text("金黄").tag("金黄")
                    Text("绿").tag("绿")
                    Text("棕").tag("棕")
                    Text("黑").tag("黑")
                    Text("其他").tag("其他")
                }
                .pickerStyle(.menu)
            }
        }
        Section("量（可选）") {
            Picker("量", selection: $amount) {
                Text("未选择").tag("")
                Text("少量").tag("少量")
                Text("中等").tag("中等")
                Text("大量").tag("大量")
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var suppSection: some View {
        Section("补剂名称") {
            TextField("例如：维生素D", text: $suppName)
        }
        Section("剂量（可选）") {
            TextField("例如：400 IU / 1 滴", text: $dose)
        }
        Section("常用") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["维生素D", "维生素AD", "维生素K1", "铁剂", "益生菌", "DHA"], id: \.self) { n in
                        Button {
                            suppName = n
                        } label: {
                            Text(n)
                                .font(.system(size: 14))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(kind.color.opacity(suppName == n ? 0.15 : 0.06),
                                            in: Capsule())
                                .foregroundColor(suppName == n ? kind.color : .primary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: 保存

    private func save() {
        if clock.running { clock.stop() }
        if clock.used { minutes = max(1, Int(ceil(Double(clock.seconds) / 60.0))) }

        switch kind {
        case .feed:
            if feedMode == "bf", minutes <= 0 {
                validationText = "请填写亲喂时长"
                showValidation = true
                return
            }
            if feedMode != "bf", ml <= 0 {
                validationText = "请填写奶量"
                showValidation = true
                return
            }
        case .diaper:
            break
        case .supp:
            if suppName.trimmingCharacters(in: .whitespaces).isEmpty {
                validationText = "请填写补剂名称"
                showValidation = true
                return
            }
        }

        var r = existing ?? Record(kind: kind, time: Date())
        r.kind = kind
        r.time = time
        r.note = note.trimmingCharacters(in: .whitespaces)
        r.feedMode = feedMode
        r.side = side
        r.minutes = minutes
        r.ml = ml
        r.storedState = storedState
        r.diaperKind = diaperKind
        r.amount = amount
        r.consistency = consistency
        r.color = color
        r.suppName = suppName.trimmingCharacters(in: .whitespaces)
        r.dose = dose.trimmingCharacters(in: .whitespaces)
        store.upsert(r)
        dismiss()
    }
}

// MARK: - 设置（导出/导入/清空）

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showShare = false
    @State private var showImport = false
    @State private var showClearConfirm = false
    @State private var importText = ""
    @State private var importResult: String?
    @State private var copied = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        UIPasteboard.general.string = store.exportJSON()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制到剪贴板 ✓" : "复制备份到剪贴板",
                              systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    }
                    Button { showShare = true } label: {
                        Label("导出为文件（存文件 / 隔空投送 / 微信）", systemImage: "square.and.arrow.up")
                    }
                    Button { showImport = true } label: {
                        Label("从备份文本导入", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("备份")
                } footer: {
                    Text("数据保存在本机。建议每周导出一次备份，存到「文件」App 或发给自己。")
                }

                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("清空全部数据")
                            Spacer()
                        }
                    }
                }

                Section("关于") {
                    Text("宝宝记录 v1.0\n喂养 / 尿布 / 补剂三类记录，含时间、统计与历史查看。\n点击任意记录可编辑或删除；顶部 ‹ › 翻看历史日期。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置与数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [backupFileURL()])
        }
        .sheet(isPresented: $showImport) {
            importView
        }
        .confirmationDialog("确定清空全部记录吗？此操作不可恢复，建议先导出备份。", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                store.clearAll()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func backupFileURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let name = "宝宝记录备份-\(f.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? store.exportJSON().data(using: .utf8)?.write(to: url)
        return url
    }

    private var importView: some View {
        NavigationView {
            VStack(spacing: 14) {
                Text("把之前导出的备份文本完整粘贴到下面，点「导入」。相同记录不会重复。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextEditor(text: $importText)
                    .font(.system(size: 12).monospaced())
                    .padding(6)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .frame(maxHeight: .infinity)
                Button {
                    let n = store.importJSON(importText)
                    importResult = n > 0 ? "成功导入 \(n) 条记录" : "内容无效：没有找到记录"
                } label: {
                    Text("导入")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                }
                .alert("导入结果", isPresented: Binding(
                    get: { importResult != nil },
                    set: { if !$0 { importResult = nil } }
                )) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text(importResult ?? "")
                }
            }
            .padding()
            .navigationTitle("导入恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showImport = false }
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - App 入口

@main
struct BabyLogApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
