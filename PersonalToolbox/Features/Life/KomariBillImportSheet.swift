import SwiftUI

/// Preview & confirm importing Komari node prices into subscription bills.
struct KomariBillImportSheet: View {
    let nodes: [KomariNode]
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ImportRow] = []
    @State private var message: String?

    struct ImportRow: Identifiable {
        var id: String { node.uuid }
        var node: KomariNode
        var selected: Bool
        var cycle: String // monthly / yearly / once
        var amount: Double
        var currency: String
        var nextDue: Date
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("勾选要导入的节点，可改周期 / 金额 / 到期日。无 price 的节点已过滤。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("节点 (\(rows.filter(\.selected).count)/\(rows.count))") {
                    if rows.isEmpty {
                        Text("没有带价格的节点").foregroundStyle(.secondary)
                    }
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $row.selected) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.node.displayName).font(.headline)
                                    HStack(spacing: 6) {
                                        if let r = row.node.region, !r.isEmpty {
                                            Text(r).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        if let g = row.node.group, !g.isEmpty {
                                            Text(g).font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                            if row.selected {
                                HStack {
                                    TextField("金额", value: $row.amount, format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("币种", text: $row.currency)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 72)
                                }
                                Picker("周期", selection: $row.cycle) {
                                    Text("月付").tag("monthly")
                                    Text("年付").tag("yearly")
                                    Text("一次性").tag("once")
                                }
                                .pickerStyle(.segmented)
                                DatePicker("下次扣费", selection: $row.nextDue, displayedComponents: .date)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if let message {
                    Section { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("导入账单预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { commit() }
                        .disabled(rows.filter(\.selected).isEmpty)
                }
            }
            .onAppear { buildRows() }
        }
    }

    private func buildRows() {
        rows = nodes.compactMap { node -> ImportRow? in
            guard let price = node.price, price > 0 else { return nil }
            let currency = (node.currency?.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 }?.uppercased() ?? "CNY"
            let due: Date
            if let exp = node.expiredAt, let d = KomariTime.parse(exp) {
                due = d
            } else {
                due = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            }
            let cycle = Self.guessCycle(from: node)
            return ImportRow(
                node: node,
                selected: true,
                cycle: cycle,
                amount: price,
                currency: currency,
                nextDue: due
            )
        }
    }

    private static func guessCycle(from node: KomariNode) -> String {
        let blob = [node.tags, node.group, node.name, node.virtualization]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if blob.contains("年") || blob.contains("year") || blob.contains("annual") {
            return "yearly"
        }
        if blob.contains("一次") || blob.contains("once") {
            return "once"
        }
        return "monthly"
    }

    private func commit() {
        var n = 0
        for row in rows where row.selected {
            var notesParts: [String] = ["来源: Komari"]
            if let region = row.node.region, !region.isEmpty { notesParts.append("地区 \(region)") }
            if let group = row.node.group, !group.isEmpty { notesParts.append("分组 \(group)") }
            if row.cycle == "yearly" { notesParts.append("周期年付") }
            let item = SubscriptionItem(
                id: SubscriptionStore.komariSubscriptionId(uuid: row.node.uuid),
                name: "VPS · \(row.node.displayName)",
                amount: row.amount,
                currency: row.currency,
                cycle: row.cycle,
                nextDue: row.nextDue,
                notes: notesParts.joined(separator: " · "),
                url: "",
                createdAt: Date()
            )
            SubscriptionStore.shared.upsert(item)
            n += 1
        }
        message = "已导入 \(n) 条"
        Haptics.success()
        onDone()
        dismiss()
    }
}
