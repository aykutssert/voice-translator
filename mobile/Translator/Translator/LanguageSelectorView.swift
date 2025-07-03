import SwiftUI

// MARK: - Language Selector View
struct LanguageSelectorView: View {
    @ObservedObject var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingCustomPicker = false
    @State private var editingLanguage: EditingLanguageType? = nil
    
    enum EditingLanguageType: Identifiable {
        case source
        case target
        
        var id: String {
            switch self {
            case .source: return "source"
            case .target: return "target"
            }
        }
    }
    
    var filteredLanguages: [SupportedLanguage] {
        let languages = SupportedLanguage.allLanguages
        
        if searchText.isEmpty {
            return languages
        } else {
            return languages.filter { language in
                language.name.localizedCaseInsensitiveContains(searchText) ||
                language.code.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.32).opacity(0.9),
                        Color(red: 0.18, green: 0.08, blue: 0.28).opacity(0.7),
                        Color(red: 0.03, green: 0.18, blue: 0.38).opacity(0.95)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerSection
                    

                    
                    // Content
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            // Current Selection
                            currentSelectionSection
                            
                            // Recent Directions
                            if !languageManager.recentDirections.isEmpty {
                                recentDirectionsSection
                            }
                            
                            // Favorite Directions
                            if !languageManager.favoriteDirections.isEmpty {
                                favoriteDirectionsSection
                            }
                            
                            // Popular Directions
                            popularDirectionsSection
                            
                            // All Languages
                            allLanguagesSection
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingCustomPicker) {
            CustomLanguagePicker(
                languageManager: languageManager,
                onSelection: { sourceLanguage, targetLanguage in
                    let newDirection = TranslationDirection(
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage
                    )
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        languageManager.setTranslationDirection(newDirection)
                    }
                    showingCustomPicker = false
                    dismiss()
                }
            )
        }
        .sheet(item: $editingLanguage) { editType in
            SingleLanguagePicker(
                languageManager: languageManager,
                currentLanguage: editType == .source ?
                    languageManager.selectedDirection.sourceLanguage :
                    languageManager.selectedDirection.targetLanguage,
                isSelectingSource: editType == .source,
                onSelection: { language in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if editType == .source {
                            let newDirection = TranslationDirection(
                                sourceLanguage: language,
                                targetLanguage: languageManager.selectedDirection.targetLanguage
                            )
                            languageManager.setTranslationDirection(newDirection)
                        } else {
                            let newDirection = TranslationDirection(
                                sourceLanguage: languageManager.selectedDirection.sourceLanguage,
                                targetLanguage: language
                            )
                            languageManager.setTranslationDirection(newDirection)
                        }
                    }
                    editingLanguage = nil
                }
            )
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            Text("Select Languages")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .foregroundColor(.white)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 15)
    }
    
    // MARK: - Search Section
    
    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            
            TextField("Search languages...", text: $searchText)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
    
    // MARK: - Current Selection Section
    
    private var currentSelectionSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Selection")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            HStack(spacing: 20) {
                // Source Language - Tıklanabilir
                Button(action: {
                    editingLanguage = .source
                }) {
                    VStack(spacing: 8) {
                        Text(languageManager.selectedDirection.sourceLanguage.flag)
                            .font(.system(size: 40))
                        
                        Text(languageManager.selectedDirection.sourceLanguage.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Tap to change")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.blue.opacity(0.5), lineWidth: 2)
                            )
                    )
                }
                
                // Swap Button
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        languageManager.swapLanguages()
                    }
                }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            Circle()
                                .fill(.blue.opacity(0.8))
                        )
                }
                
                // Target Language - Tıklanabilir
                Button(action: {
                    editingLanguage = .target
                }) {
                    VStack(spacing: 8) {
                        Text(languageManager.selectedDirection.targetLanguage.flag)
                            .font(.system(size: 40))
                        
                        Text(languageManager.selectedDirection.targetLanguage.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Tap to change")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.green.opacity(0.5), lineWidth: 2)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quick Actions")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Custom Direction Button
                    Button(action: {
                        showingCustomPicker = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            Text("Custom")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .frame(width: 80, height: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.blue.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Popular directions
                    ForEach(LanguageManager.popularDirections.prefix(5), id: \.id) { direction in
                        DirectionCard(
                            direction: direction,
                            isSelected: direction.sourceLanguage.code == languageManager.selectedDirection.sourceLanguage.code &&
                                       direction.targetLanguage.code == languageManager.selectedDirection.targetLanguage.code,
                            action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    languageManager.setTranslationDirection(direction)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.leading, -20)
            .padding(.trailing, -20)
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Recent Directions Section
    
    private var recentDirectionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Clear") {
                    withAnimation {
                        languageManager.recentDirections.removeAll()
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(languageManager.recentDirections.prefix(4), id: \.id) { direction in
                    DirectionListItem(
                        direction: direction,
                        isSelected: direction.sourceLanguage.code == languageManager.selectedDirection.sourceLanguage.code &&
                                   direction.targetLanguage.code == languageManager.selectedDirection.targetLanguage.code,
                        isFavorite: languageManager.isFavorite(direction),
                        onSelect: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                languageManager.setTranslationDirection(direction)
                            }
                        },
                        onFavorite: {
                            withAnimation {
                                if languageManager.isFavorite(direction) {
                                    languageManager.removeFromFavorites(direction)
                                } else {
                                    languageManager.addToFavorites(direction)
                                }
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Favorite Directions Section
    
    private var favoriteDirectionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Favorites")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(languageManager.favoriteDirections, id: \.id) { direction in
                    DirectionListItem(
                        direction: direction,
                        isSelected: direction.sourceLanguage.code == languageManager.selectedDirection.sourceLanguage.code &&
                                   direction.targetLanguage.code == languageManager.selectedDirection.targetLanguage.code,
                        isFavorite: true,
                        onSelect: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                languageManager.setTranslationDirection(direction)
                            }
                        },
                        onFavorite: {
                            withAnimation {
                                languageManager.removeFromFavorites(direction)
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Popular Directions Section
    
    private var popularDirectionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Popular Combinations")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(LanguageManager.popularDirections, id: \.id) { direction in
                    DirectionListItem(
                        direction: direction,
                        isSelected: direction.sourceLanguage.code == languageManager.selectedDirection.sourceLanguage.code &&
                                   direction.targetLanguage.code == languageManager.selectedDirection.targetLanguage.code,
                        isFavorite: languageManager.isFavorite(direction),
                        onSelect: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                languageManager.setTranslationDirection(direction)
                            }
                        },
                        onFavorite: {
                            withAnimation {
                                if languageManager.isFavorite(direction) {
                                    languageManager.removeFromFavorites(direction)
                                } else {
                                    languageManager.addToFavorites(direction)
                                }
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - All Languages Section
    
    private var allLanguagesSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("All Languages")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(filteredLanguages, id: \.id) { language in
                    LanguageCard(language: language) {
                        showingCustomPicker = true
                    }
                }
            }
        }
    }
}

// MARK: - Single Language Picker (for editing source/target)
struct SingleLanguagePicker: View {
    @ObservedObject var languageManager: LanguageManager
    let currentLanguage: SupportedLanguage
    let isSelectingSource: Bool
    let onSelection: (SupportedLanguage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var filteredLanguages: [SupportedLanguage] {
        let languages = isSelectingSource ?
            SupportedLanguage.allLanguages.filter { $0.code != languageManager.selectedDirection.targetLanguage.code } :
            SupportedLanguage.allLanguages.filter { $0.code != languageManager.selectedDirection.sourceLanguage.code }
        
        if searchText.isEmpty {
            return languages
        } else {
            return languages.filter { language in
                language.name.localizedCaseInsensitiveContains(searchText) ||
                language.code.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.32).opacity(0.9),
                        Color(red: 0.18, green: 0.08, blue: 0.28).opacity(0.7),
                        Color(red: 0.03, green: 0.18, blue: 0.38).opacity(0.95)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        HStack {
                            Button("Cancel") {
                                dismiss()
                            }
                            .foregroundColor(.white.opacity(0.8))
                            
                            Spacer()
                            
                            Text("Change \(isSelectingSource ? "Source" : "Target") Language")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Spacer()
                        
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Current selection
                        HStack(spacing: 12) {
                            VStack(spacing: 4) {
                                Text(currentLanguage.flag)
                                    .font(.title2)
                                Text(currentLanguage.name)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .opacity(0.6)
                            
                            Image(systemName: "arrow.right")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("?")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.bottom, 10)
                    }
                    
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Search languages...", text: $searchText)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    
                    // Language Grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(filteredLanguages, id: \.id) { language in
                                LanguageSelectionCard(
                                    language: language,
                                    isSelected: language.code == currentLanguage.code,
                                    action: {
                                        onSelection(language)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top,15)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Custom Language Picker
struct CustomLanguagePicker: View {
    @ObservedObject var languageManager: LanguageManager
    let onSelection: (SupportedLanguage, SupportedLanguage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSourceLanguage: SupportedLanguage?
    @State private var selectedTargetLanguage: SupportedLanguage?
    @State private var currentStep: SelectionStep = .selectSource
    @State private var searchText = ""
    
    enum SelectionStep {
        case selectSource
        case selectTarget
    }
    
    var filteredLanguages: [SupportedLanguage] {
        let languages = currentStep == .selectSource ?
            SupportedLanguage.allLanguages :
            SupportedLanguage.allLanguages.filter { $0.code != selectedSourceLanguage?.code }
        
        if searchText.isEmpty {
            return languages
        } else {
            return languages.filter { language in
                language.name.localizedCaseInsensitiveContains(searchText) ||
                language.code.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.32).opacity(0.9),
                        Color(red: 0.18, green: 0.08, blue: 0.28).opacity(0.7),
                        Color(red: 0.03, green: 0.18, blue: 0.38).opacity(0.95)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress indicator
                    progressIndicator
                    
                    // Header
                    headerSection
                    
                    // Search
                    searchSection
                    
                    // Language Grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(filteredLanguages, id: \.id) { language in
                                LanguageSelectionCard(
                                    language: language,
                                    isSelected: currentStep == .selectSource ?
                                        selectedSourceLanguage?.code == language.code :
                                        selectedTargetLanguage?.code == language.code,
                                    action: {
                                        selectLanguage(language)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 20) {
            // Step 1
            HStack(spacing: 8) {
                Circle()
                    .fill(currentStep == .selectSource ? Color.blue : Color.green)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text("1")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    )
                
                Text("Source")
                    .font(.caption)
                    .foregroundColor(currentStep == .selectSource ? .white : .white.opacity(0.7))
            }
            
            Rectangle()
                .fill(currentStep == .selectTarget ? Color.green : Color.white.opacity(0.3))
                .frame(height: 2)
                .frame(maxWidth: 60)
            
            // Step 2
            HStack(spacing: 8) {
                Circle()
                    .fill(currentStep == .selectTarget ? Color.blue : Color.white.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text("2")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(currentStep == .selectTarget ? .white : .white.opacity(0.7))
                    )
                
                Text("Target")
                    .font(.caption)
                    .foregroundColor(currentStep == .selectTarget ? .white : .white.opacity(0.7))
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text(currentStep == .selectSource ? "Select Source Language" : "Select Target Language")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if currentStep == .selectTarget {
                    Button("Back") {
                        withAnimation {
                            currentStep = .selectSource
                            searchText = ""
                        }
                    }
                    .foregroundColor(.white.opacity(0.8))
                } else {
                    Color.clear.frame(width: 50)
                }
            }
            .padding(.horizontal, 20)
            
            // Selected languages display
            if selectedSourceLanguage != nil {
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text(selectedSourceLanguage!.flag)
                            .font(.title2)
                        Text(selectedSourceLanguage!.name)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                    
                    if let targetLang = selectedTargetLanguage {
                        VStack(spacing: 4) {
                            Text(targetLang.flag)
                                .font(.title2)
                            Text(targetLang.name)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    } else {
                        VStack(spacing: 4) {
                            Text("?")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Select target")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - Search Section
    
    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            
            TextField("Search languages...", text: $searchText)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    
    // MARK: - Helper Methods
    
    private func selectLanguage(_ language: SupportedLanguage) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if currentStep == .selectSource {
                selectedSourceLanguage = language
                currentStep = .selectTarget
                searchText = ""
            } else {
                selectedTargetLanguage = language
                if let source = selectedSourceLanguage, let target = selectedTargetLanguage {
                    onSelection(source, target)
                }
            }
        }
    }
}

// MARK: - Language Selection Card Component
struct LanguageSelectionCard: View {
    let language: SupportedLanguage
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(language.flag)
                    .font(.title2)
                
                Text(language.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                
                Text(language.code.uppercased())
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(height: 90)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.3) : Color.clear)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? .blue : .white.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Direction Card Component
struct DirectionCard: View {
    let direction: TranslationDirection
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(direction.sourceLanguage.flag)
                        .font(.caption)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    Text(direction.targetLanguage.flag)
                        .font(.caption)
                }
                
                Text(direction.sourceLanguage.code.uppercased())
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.3) : Color.clear)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? .blue : .white.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Direction List Item Component
struct DirectionListItem: View {
    let direction: TranslationDirection
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onFavorite: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    Button(action: onFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundColor(isFavorite ? .red : .white.opacity(0.6))
                    }
                }
                
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(direction.sourceLanguage.flag)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Text(direction.targetLanguage.flag)
                    }
                    
                    Text(direction.sourceLanguage.name)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("to")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text(direction.targetLanguage.name)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(12)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.3) : Color.clear)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? .blue : .white.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Language Card Component
struct LanguageCard: View {
    let language: SupportedLanguage
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(language.flag)
                    .font(.title2)
                
                Text(language.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
}

// Dosyanın en sonuna ekleyin:

// MARK: - Preview
struct LanguageSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        LanguageSelectorView(languageManager: LanguageManager())
            .preferredColorScheme(.dark)
    }
}
