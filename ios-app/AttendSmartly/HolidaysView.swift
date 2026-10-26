import SwiftUI
import SwiftData

struct HolidaysView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Holiday.date) private var holidays: [Holiday]
    @State private var showAdd = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if holidays.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "party.popper")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(DashboardPalette.green)
                    Text("No holidays").font(.title3.bold())
                    Text("Holidays hide that day's classes from Home.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(holidays) { holiday in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(holiday.title).font(.headline)
                            Text(DateUtils.prettyDate(holiday.date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(holidays[index]) }
                        do { try context.save() } catch { errorText = error.localizedDescription }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Pastel.background)
        .navigationTitle("Holidays")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Label("Add holiday", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddHolidayView() }
        .alert("Couldn't save", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }
}

struct AddHolidayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date = Date()
    @State private var multiDay = false
    @State private var endDate = Date()
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Diwali)", text: $title)
                    DatePicker(multiDay ? "From" : "Date", selection: $date, displayedComponents: .date)
                    Toggle("Multiple days", isOn: $multiDay)
                    if multiDay {
                        DatePicker("Until", selection: $endDate, in: date..., displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("New Holiday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: date)
        let last = multiDay ? max(calendar.startOfDay(for: endDate), day) : day
        var created = 0
        while day <= last && created < 60 {
            context.insert(Holiday(date: DateUtils.isoString(day), title: name))
            created += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        do {
            try context.save()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
