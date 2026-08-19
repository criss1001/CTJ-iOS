import SwiftUI

struct ContentView: View {
    @StateObject private var model = CTJModel()
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage:"house.fill") }
            PlayerEditorView().tabItem { Label("Players", systemImage:"person.3.fill") }
            ShotEditorView().tabItem { Label("Shots", systemImage:"scope") }
            PS1DiscView().tabItem { Label("PS1 BIN", systemImage:"opticaldiscdrive.fill") }
        }
        .environmentObject(model)
    }
}

struct HomeView: View {
    @EnvironmentObject var model: CTJModel
    var body: some View { NavigationStack { Form {
        Section("CTJ Modern Tool v42") {
            Text("iOS native port")
            Text("Player Editor • Shot Editor • PS1 BIN native patching")
        }
        Section("Files") {
            Button("Import TEAMDAT") { model.importKind = .team; model.showImporter = true }
            Button("Import CAPTIN.EXE") { model.importKind = .captin; model.showImporter = true }
        }
    }.navigationTitle("CTJ v42") }
    .fileImporter(isPresented:$model.showImporter, allowedContentTypes:[.data], allowsMultipleSelection:false) { result in model.handleImport(result) }
    }
}

struct PS1DiscView: View {
    @EnvironmentObject var model: CTJModel
    @State private var showDiscImporter = false
    @State private var selectedPath = ""
    var body: some View { NavigationStack { Form {
        Section("PS1 BIN / ISO") {
            Button("فتح BIN / ISO") { showDiscImporter = true }
            if !model.discName.isEmpty { Text(model.discName).font(.caption) }
            if let image = model.discImage {
                Text("Sector size: \(image.sectorSize)")
                Text("Files: \(image.files.count)")
            }
        }
        if let image = model.discImage {
            Section("Game files") {
                Picker("File", selection:$selectedPath) {
                    Text("اختر ملف").tag("")
                    ForEach(image.files.map{$0.path}.sorted(), id:\.self) { Text($0).tag($0) }
                }
                Button("تحميل الملف إلى المحرر") { if !selectedPath.isEmpty { model.loadDiscFile(selectedPath) } }
                Button("حقن الملف المعدل داخل BIN") { if !selectedPath.isEmpty { model.injectCurrentFile(selectedPath) } }
                Button("تصدير BIN المعدل") { model.exportPatchedDisc() }
            }
        }
    }.navigationTitle("PS1 BIN") }
    .fileImporter(isPresented:$showDiscImporter, allowedContentTypes:[.data], allowsMultipleSelection:false) { model.handleDiscImport($0) }
    }
}

struct PlayerEditorView: View {
    @EnvironmentObject var model: CTJModel
    @State private var bytes: [UInt8] = Array(repeating: 0, count: 16)
    var body: some View { NavigationStack { Form {
        Section("اللاعب") {
            Stepper("Player Slot: \(model.selectedPlayer)", value:$model.selectedPlayer, in:0...63)
            Button("تحميل السجل") { bytes=model.playerRecord(model.selectedPlayer) }
        }
        Section("Real Player Stats") {
            stat("Player ID",0,0...255); stat("Shirt",1,0...30)
            Picker("Position", selection: Binding(get:{Int(bytes[2])},set:{bytes[2]=UInt8($0)})) { Text("FW").tag(0); Text("MF").tag(1); Text("DF").tag(2); Text("GK").tag(3) }
            stat("Level",4,0...255)
            Stepper("Stamina: \(Int(bytes[5])*2)", value: Binding(get:{Int(bytes[5])},set:{bytes[5]=UInt8(clamping:$0)}), in:0...255)
            stat("Mobility",6,0...255); stat("Attack",7,0...255); stat("Technique",8,0...255); stat("Judgment",9,0...255); stat("Spirit",10,0...255)
        }
        Section("TEAMDAT raw 16 bytes") { ForEach(0..<16,id:\.self) { i in stat(String(format:"B%02d",i),i,0...255) } }
        Button("💾 حفظ تعديل اللاعب") { model.savePlayer(model.selectedPlayer, bytes:bytes) }.disabled(model.teamData.isEmpty)
    }.navigationTitle("Player Editor") }.onAppear { bytes=model.playerRecord(model.selectedPlayer) }.onChange(of:model.selectedPlayer){_,_ in bytes=model.playerRecord(model.selectedPlayer)} }
    @ViewBuilder func stat(_ name:String,_ i:Int,_ range:ClosedRange<Int>)->some View { Stepper("\(name): \(bytes[i])", value:Binding(get:{Int(bytes[i])},set:{bytes[i]=UInt8(clamping:$0)}), in:range) }
}

struct ShotEditorView: View {
    @EnvironmentObject var model: CTJModel
    @State private var source: ShotRecord?
    @State private var target: ShotRecord?
    @State private var mode: ShotMode = .copy
    var unique:[ShotRecord] { var seen=Set<String>(); return model.shots.sorted{$0.offset<$1.offset}.filter { seen.insert("\($0.playerID)-\($0.shotSlot)").inserted } }
    var body: some View { NavigationStack { VStack {
        if model.captinData.isEmpty { ContentUnavailableView("Import CAPTIN.EXE", systemImage:"doc.badge.plus") }
        else { List(unique) { rec in
            Button { if source == nil { source=rec } else { target=rec } } label: {
                HStack { VStack(alignment:.leading){ Text("Player \(rec.playerID) • Shot \(rec.shotSlot)"); Text(String(format:"Offset 0x%X",rec.offset)).font(.caption) }; Spacer(); if source?.id==rec.id { Image(systemName:"1.circle.fill") }; if target?.id==rec.id { Image(systemName:"2.circle.fill") } }
            }
        }
        Picker("Mode",selection:$mode){ Text("Copy").tag(ShotMode.copy); Text("Duplicate").tag(ShotMode.duplicate); Text("Swap").tag(ShotMode.swap); Text("Delete").tag(ShotMode.delete) }.pickerStyle(.segmented).padding()
        Button("Apply") { model.applyShot(mode:mode, source:source, target:target); source=nil; target=nil }.buttonStyle(.borderedProminent).padding(.bottom)
        }
    }.navigationTitle("Shot ID Editor v42") }
}
