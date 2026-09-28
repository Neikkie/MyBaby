import CoreData
import SwiftUI

/// Name, birthday and theme fields for one baby, used by onboarding and "Add Baby".
struct BabyDetailsFields: View {
    @Binding var name: String
    @Binding var hasBirthday: Bool
    @Binding var birthday: Date
    @Binding var gender: BabyGender
    var title: String?

    @FocusState private var isNameFocused: Bool

    /// Age picture for the avatar, based on the birthday entered so far.
    private var picture: String {
        guard hasBirthday, let age = BabyAge(birthdayInterval: birthday.timeIntervalSince1970) else { return "👶" }
        return age.stagePicture(for: gender)
    }

    var body: some View {
        VStack(spacing: 22) {
            // A live preview of the baby's theme and stage.
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(gender.theme.backgroundGradient)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                    .frame(width: 104, height: 104)
                    .overlay {
                        Text(picture)
                            .font(.system(size: 54))
                            .contentTransition(.opacity)
                    }
                    .shadow(color: gender.theme.accent.opacity(0.25), radius: 14, y: 6)
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(gender.theme.titleGradient, in: .circle)
                    .offset(x: 4, y: 4)
            }
            .accessibilityHidden(true)
            .animation(.spring(duration: 0.4, bounce: 0.35), value: gender)

            if let title {
                Text(title)
                    .font(.title3.bold())
                    .fontDesign(.rounded)
            }

            // Name and birthday together in one grouped card.
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(gender.theme.accent)
                        .frame(width: 24)
                    TextField("Baby's name", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .font(.body.weight(.medium))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)

                Divider().padding(.leading, 52)

                Toggle(isOn: $hasBirthday.animation(.spring(duration: 0.35))) {
                    HStack(spacing: 12) {
                        Image(systemName: "birthday.cake.fill")
                            .foregroundStyle(gender.theme.accent)
                            .frame(width: 24)
                        Text("Birthday")
                            .font(.body.weight(.medium))
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)

                if hasBirthday {
                    Divider().padding(.leading, 52)
                    DatePicker(selection: $birthday, in: ...Date.now, displayedComponents: .date) {
                        Text("Born on")
                            .foregroundStyle(.secondary)
                            .padding(.leading, 36)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(.background, in: .rect(cornerRadius: 22, style: .continuous))
            .clipShape(.rect(cornerRadius: 22, style: .continuous))

            // Theme picker.
            VStack(spacing: 10) {
                Text("Boy, Girl or Both?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(BabyGender.allCases) { option in
                        ThemeChip(option: option, isSelected: gender == option) {
                            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { gender = option }
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: gender)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A theme choice: the theme's colors, with a clear selected state that never gets clipped.
private struct ThemeChip: View {
    let option: BabyGender
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let theme = option.theme
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(theme.titleGradient)
                    .symbolEffect(.bounce, value: isSelected)
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(theme.backgroundGradient) : AnyShapeStyle(.background))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2.5)
            }
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("\(option.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Adds another baby (e.g. a new sibling) and switches to them.
struct AddBabySheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SelectedBaby.storageKey, store: SelectedBaby.defaults) private var selectedBabyID = ""

    @State private var name = ""
    @State private var hasBirthday = true
    @State private var birthday = Date.now
    @State private var gender: BabyGender = .both

    var body: some View {
        NavigationStack {
            ScrollView {
                BabyDetailsFields(name: $name, hasBirthday: $hasBirthday, birthday: $birthday, gender: $gender)
                    .padding()
            }
            .background { ThemedBackground() }
            .environment(\.appTheme, gender.theme)
            .navigationTitle("Add Baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) {
                        let baby = Baby(
                            context: context,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            birthday: hasBirthday ? birthday : nil,
                            gender: gender
                        )
                        try? context.save()
                        withAnimation { selectedBabyID = baby.babyID?.uuidString ?? "" }
                        dismiss()
                    }
                }
            }
        }
    }
}
