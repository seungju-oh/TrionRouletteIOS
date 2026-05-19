import SwiftUI

// --- 1. 색상 및 데이터 모델 ---
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 08) & 0xff) / 255, blue: Double((hex >> 00) & 0xff) / 255, opacity: alpha)
    }
}

let rouletteColors: [Color] = [
    Color(hex: 0xFFFFB3BA), Color(hex: 0xFFAFF8D8), Color(hex: 0xFFBAE1FF), Color(hex: 0xFFFFFFBA),
    Color(hex: 0xFFD1BAFF), Color(hex: 0xFFFFDFBA), Color(hex: 0xFFE7FFAC), Color(hex: 0xFFFFC9DE),
    Color(hex: 0xFFC4FAF8), Color(hex: 0xFFB5B9FF), Color(hex: 0xFFFFDAB9), Color(hex: 0xFFE2F0CB)
]

func getRouletteColor(index: Int, totalItems: Int) -> Color {
    if totalItems == 0 { return .gray }
    var colorIndex = index % rouletteColors.count
    if index == totalItems - 1 && colorIndex == 0 && totalItems > 1 { colorIndex = 1 }
    return rouletteColors[colorIndex]
}

enum RouletteMode { case A, B, C }

struct RouletteItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String = ""
    var probText: String = ""
}

// --- 2. 룰렛 휠 캔버스 뷰 ---
struct RouletteWheel: View {
    var displayItems: [RouletteItem]
    var allItems: [RouletteItem]
    var mode: RouletteMode
    var rotationDegree: Double
    
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            var startAngle = Angle.zero
            
            let totalProb = mode == .C ? displayItems.reduce(0) { $0 + (Double($1.probText) ?? 0) } : 0
            
            for item in displayItems {
                let sweepAngle: Angle
                if mode == .C && totalProb > 0 {
                    let prob = Double(item.probText) ?? 0
                    sweepAngle = .degrees((prob / totalProb) * 360)
                } else {
                    sweepAngle = .degrees(360.0 / Double(displayItems.count))
                }
                
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + sweepAngle, clockwise: false)
                path.closeSubpath()
                
                let originalIndex = allItems.firstIndex(of: item) ?? 0
                context.fill(path, with: .color(getRouletteColor(index: originalIndex, totalItems: allItems.count)))
                startAngle += sweepAngle
            }
        }
        .rotationEffect(.degrees(rotationDegree))
        // [Appium ID] 캔버스 영역
        .accessibilityIdentifier("canvas_roulette_wheel")
    }
}

// --- 3. 메인 화면 ---
struct ContentView: View {
    @State private var mode: RouletteMode = .A
    @State private var items: [RouletteItem] = [RouletteItem(), RouletteItem()]
    @State private var skipAnimation: Bool = false
    @State private var rotationDegree: Double = 0.0
    @State private var eliminatedIds: Set<UUID> = []
    
    @State private var isSpinning: Bool = false
    
    @State private var showResultDialog: Bool = false
    @State private var resultText: String = ""
    
    @State private var showResetDialog: Bool = false
    @State private var showSaveDialog: Bool = false
    @State private var showOverwriteDialog: Bool = false
    @State private var presetNameToSave: String = ""
    
    @State private var showLoadSheet: Bool = false
    @State private var savedPresetNames: [String] = []
    
    var currentDisplayItems: [RouletteItem] {
        if mode == .B { return items.filter { !eliminatedIds.contains($0.id) } }
        return items
    }
    
    var totalProb: Double {
        items.reduce(0) { $0 + (Double($1.probText) ?? 0.0) }
    }
    
    var isModeCValid: Bool {
        abs(totalProb - 100.0) < 0.01
    }
    
    var canSpin: Bool {
        let hasEnoughItems = items.count >= 2 && !currentDisplayItems.isEmpty
        let hasValidText = currentDisplayItems.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let validCMode = (mode != .C || isModeCValid)
        return hasEnoughItems && hasValidText && validCMode && !isSpinning
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    Picker("모드 선택", selection: $mode) {
                        // [Appium ID] 라디오 버튼 대체 요소 (세그먼트 컨트롤)
                        Text("기본 (A)").tag(RouletteMode.A).accessibilityIdentifier("radio_mode_a")
                        Text("서바이벌 (B)").tag(RouletteMode.B).accessibilityIdentifier("radio_mode_b")
                        Text("확률 (C)").tag(RouletteMode.C).accessibilityIdentifier("radio_mode_c")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top)
                    .onChange(of: mode) {
                        eliminatedIds.removeAll()
                        rotationDegree = 0
                    }
                    
                    ZStack(alignment: .top) {
                        if items.count >= 2 && !currentDisplayItems.isEmpty {
                            RouletteWheel(displayItems: currentDisplayItems, allItems: items, mode: mode, rotationDegree: rotationDegree)
                                .frame(width: 250, height: 250)
                                .clipShape(Circle())
                            
                            Image(systemName: "arrowtriangle.down.fill")
                                .foregroundColor(.red)
                                .font(.largeTitle)
                                .offset(y: -20)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 250, height: 250)
                                .overlay(Text("항목을 2개 이상 입력해주세요.").foregroundColor(.gray))
                        }
                    }
                    .padding(.vertical)
                    
                    VStack(spacing: 16) {
                        Toggle("룰렛 회전 생략", isOn: $skipAnimation)
                            .padding(.horizontal, 40)
                            // [Appium ID] 애니메이션 스킵 체크박스
                            .accessibilityIdentifier("chk_skip_animation")
                            .disabled(isSpinning)
                        
                        Button(action: { spinRoulette() }) {
                            Text("START SPIN")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(canSpin ? Color.blue : Color.gray)
                                .cornerRadius(10)
                        }
                        .disabled(!canSpin)
                        .padding(.horizontal, 40)
                        // [Appium ID] 스핀 버튼 (활성/비활성에 따라 ID 동적 변경)
                        .accessibilityIdentifier(canSpin ? "btn_spin_enabled" : "btn_spin_disabled")
                    }
                    
                    HStack {
                        Text("항목 관리")
                            .font(.headline)
                        Spacer()
                        
                        Button(action: {
                            hideKeyboard()
                            showResetDialog = true
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.gray)
                        }
                        .padding(.trailing, 8)
                        // [Appium ID] 전체 초기화 버튼
                        .accessibilityIdentifier("btn_reset_all")
                        .disabled(isSpinning)
                        
                        Button(action: { items.append(RouletteItem()) }) { Image(systemName: "plus") }
                        // [Appium ID] 항목 추가 버튼
                        .accessibilityIdentifier("btn_add_item")
                        .disabled(isSpinning)
                    }
                    .padding(.horizontal)
                    
                    if mode == .C {
                        HStack {
                            Text("현재 확률 총합: \(String(format: "%.2f", totalProb))%")
                                .foregroundColor(isModeCValid ? .blue : .red)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            if let index = items.firstIndex(where: { $0.id == item.id }) {
                                let isEliminated = mode == .B && eliminatedIds.contains(item.id)
                                
                                HStack {
                                    Circle()
                                        .fill(getRouletteColor(index: index, totalItems: items.count))
                                        .frame(width: 24, height: 24)
                                        .opacity(isEliminated ? 0.3 : 1.0)
                                    
                                    TextField("항목 입력", text: $items[index].text)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .foregroundColor(isEliminated ? .gray : nil)
                                        .opacity(isEliminated ? 0.5 : 1.0)
                                        .disabled(isEliminated || isSpinning)
                                        // [Appium ID] 텍스트 입력창 (상태에 따른 동적 ID)
                                        .accessibilityIdentifier(isEliminated ? "input_item_text_\(index)_disabled" : "input_item_text_\(index)")
                                    
                                    if mode == .C {
                                        TextField("%", text: Binding(
                                            get: { index < items.count ? items[index].probText : "" },
                                            set: { newValue in
                                                if index < items.count { items[index].probText = newValue }
                                            }
                                        ))
                                        .keyboardType(.decimalPad)
                                        .frame(width: 60)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .foregroundColor(isEliminated ? .gray : nil)
                                        .disabled(isSpinning)
                                        // [Appium ID] 확률 입력창 (상태에 따른 동적 ID)
                                        .accessibilityIdentifier(isEliminated ? "input_item_prob_\(index)_disabled" : "input_item_prob_\(index)")
                                        .onChange(of: index < items.count ? items[index].probText : "") { oldValue, newValue in
                                            let pattern = "^\\d*\\.?\\d{0,2}$"
                                            let sanitized = newValue.replacingOccurrences(of: ",", with: ".")
                                            
                                            if !sanitized.isEmpty && sanitized.range(of: pattern, options: .regularExpression) == nil {
                                                if index < items.count {
                                                    items[index].probText = oldValue
                                                }
                                            } else if sanitized != newValue {
                                                if index < items.count {
                                                    items[index].probText = sanitized
                                                }
                                            }
                                        }
                                    }
                                    
                                    Button(action: {
                                        if items.count > 2 && index < items.count {
                                            items.remove(at: index)
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(items.count > 2 ? .red : .gray)
                                            .opacity(isEliminated ? 0.3 : 1.0)
                                    }
                                    .disabled(items.count <= 2 || isEliminated || isSpinning)
                                    // [Appium ID] 개별 항목 삭제 버튼 (상태에 따른 동적 ID)
                                    .accessibilityIdentifier(isEliminated ? "btn_delete_item_\(index)_disabled" : "btn_delete_item_\(index)")
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .onTapGesture { hideKeyboard() }
            .navigationTitle("TrionRoulette")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("저장") {
                            showSaveDialog = true
                        }
                        // [Appium ID] 상단바 저장 버튼
                        .accessibilityIdentifier("btn_topbar_save")
                        .disabled(isSpinning)
                        
                        Button("불러오기") {
                            showLoadSheet = true
                        }
                        // [Appium ID] 상단바 불러오기 버튼
                        .accessibilityIdentifier("btn_topbar_load")
                        .disabled(isSpinning)
                    }
                }
            }
            // --- 다이얼로그 관리 ---
            .alert("초기화", isPresented: $showResetDialog) {
                Button("취소", role: .cancel) { }
                    // [Appium ID] 초기화 취소 버튼
                    .accessibilityIdentifier("btn_dialog_reset_cancel")
                
                Button("초기화", role: .destructive) {
                    items = [RouletteItem(), RouletteItem()]
                    eliminatedIds.removeAll()
                    rotationDegree = 0
                }
                // [Appium ID] 초기화 승인 버튼
                .accessibilityIdentifier("btn_dialog_reset_confirm")
            } message: {
                Text("모든 항목을 지울까요?")
            }
            
            .alert("Result", isPresented: $showResultDialog) {
                Button("확인") { showResultDialog = false }
                    // [Appium ID] 결과 확인 팝업 확인 버튼
                    .accessibilityIdentifier("btn_dialog_result_confirm")
            } message: {
                Text(resultText).font(.largeTitle)
            }
            
            .alert("프리셋 저장", isPresented: $showSaveDialog) {
                TextField("이름 입력", text: $presetNameToSave)
                    // [Appium ID] 프리셋 저장 이름 입력창
                    .accessibilityIdentifier("input_preset_name")
                
                Button("취소", role: .cancel) {
                    presetNameToSave = ""
                }
                // [Appium ID] 프리셋 저장 취소 버튼
                .accessibilityIdentifier("btn_dialog_save_cancel")
                
                Button("저장") {
                    if !presetNameToSave.isEmpty {
                        let existingNames = loadPresetNames()
                        if existingNames.contains(presetNameToSave) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showOverwriteDialog = true
                            }
                        } else {
                            savePreset(name: presetNameToSave)
                            presetNameToSave = ""
                        }
                    }
                }
                // [Appium ID] 프리셋 저장 승인 버튼
                .accessibilityIdentifier("btn_dialog_save_confirm")
            }
            
            .alert("이름 중복", isPresented: $showOverwriteDialog) {
                Button("취소", role: .cancel) {
                    presetNameToSave = ""
                }
                // [Appium ID] 덮어쓰기 취소 버튼
                .accessibilityIdentifier("btn_dialog_overwrite_cancel")
                
                Button("덮어쓰기", role: .destructive) {
                    savePreset(name: presetNameToSave)
                    presetNameToSave = ""
                }
                // [Appium ID] 덮어쓰기 승인 버튼
                .accessibilityIdentifier("btn_dialog_overwrite_confirm")
            } message: {
                Text("'\(presetNameToSave)'은(는) 이미 존재하는 프리셋입니다. 정말 덮어쓰시겠습니까?")
            }
            
            .sheet(isPresented: $showLoadSheet) {
                NavigationStack {
                    List {
                        ForEach(savedPresetNames, id: \.self) { name in
                            HStack {
                                Text(name)
                                Spacer()
                                Button(action: {
                                    loadPresetItems(name: name)
                                    showLoadSheet = false
                                }) {
                                    Text("불러오기")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                // [Appium ID] 프리셋 불러오기 행(Row)
                                .accessibilityIdentifier("row_load_preset_\(name)")
                            }
                        }
                        .onDelete(perform: deletePreset)
                    }
                    .navigationTitle("프리셋 불러오기")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("닫기") { showLoadSheet = false }
                            // [Appium ID] 불러오기 창 닫기 버튼
                            .accessibilityIdentifier("btn_dialog_load_close")
                        }
                    }
                    .onAppear {
                        savedPresetNames = loadPresetNames()
                    }
                }
            }
        }
    }
    
    // --- 룰렛 로직 ---
    func spinRoulette() {
        if isSpinning { return }
        
        hideKeyboard()
        let winnerIndex = calculateWinner()
        if winnerIndex == -1 { return }
        
        isSpinning = true
        
        let winner = currentDisplayItems[winnerIndex]
        let randomExtraRotation = Double.random(in: 0...360)
        let finalRotation = rotationDegree + 1800 + randomExtraRotation
        
        let showResult = {
            isSpinning = false
            
            resultText = "결과: '\(winner.text)'"
            showResultDialog = true
            
            if mode == .B {
                eliminatedIds.insert(winner.id)
                if eliminatedIds.count >= items.count {
                    eliminatedIds.removeAll()
                    resultText += "\n(잔여 항목이 없습니다. 전체 항목을 재활성화 합니다.)"
                }
            }
        }
        
        if skipAnimation {
            rotationDegree = finalRotation.truncatingRemainder(dividingBy: 360)
            showResult()
        } else {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 3.0)) {
                rotationDegree = finalRotation
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { showResult() }
        }
    }
    
    func calculateWinner() -> Int {
        if currentDisplayItems.isEmpty { return -1 }
        if currentDisplayItems.count == 1 { return 0 }
        
        if mode == .C {
            let random = Double.random(in: 0...100)
            var cumulative = 0.0
            for (i, item) in currentDisplayItems.enumerated() {
                cumulative += Double(item.probText) ?? 0.0
                if random <= cumulative { return i }
            }
        }
        return Int.random(in: 0..<currentDisplayItems.count)
    }
    
    // --- 기기 저장소(UserDefaults) 로직 ---
    func savePreset(name: String) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(items) {
            UserDefaults.standard.set(encoded, forKey: "preset_\(name)")
            var names = loadPresetNames()
            if !names.contains(name) {
                names.append(name)
                UserDefaults.standard.set(names, forKey: "preset_names")
            }
        }
    }
    
    func loadPresetNames() -> [String] {
        return UserDefaults.standard.stringArray(forKey: "preset_names") ?? []
    }
    
    func loadPresetItems(name: String) {
        if let data = UserDefaults.standard.data(forKey: "preset_\(name)") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([RouletteItem].self, from: data) {
                items = decoded.map { RouletteItem(id: UUID(), text: $0.text, probText: $0.probText) }
                eliminatedIds.removeAll()
                rotationDegree = 0
            }
        }
    }
    
    func deletePreset(at offsets: IndexSet) {
        for index in offsets {
            let name = savedPresetNames[index]
            UserDefaults.standard.removeObject(forKey: "preset_\(name)")
        }
        savedPresetNames.remove(atOffsets: offsets)
        UserDefaults.standard.set(savedPresetNames, forKey: "preset_names")
    }
}

// --- 4. 편의 기능 ---
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    ContentView()
}
