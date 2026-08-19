import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: CTJModel
    var body: some View {
        TabView {
            HomeView().tabItem { Label("الرئيسية", systemImage: "house.fill") }
            DiscToolsView().tabItem { Label("PS1 BIN", systemImage: "opticaldisc.fill") }
            PlayerEditorView().tabItem { Label("اللاعب", systemImage: "person.crop.rectangle") }
            ShotEditorView().tabItem { Label("التسديدات", systemImage: "soccerball") }
            TeamLogosView().tabItem { Label("الفرق", systemImage: "shield.lefthalf.filled") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.medium ... .xxxLarge)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.status.isEmpty {
                Text(model.status).font(.caption).lineLimit(1).padding(.horizontal,12).padding(.vertical,5)
                    .background(.ultraThinMaterial).clipShape(Capsule()).padding(.top,2)
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var model: CTJModel
    @State private var importTeam = false
    @State private var importCaptin = false
    @State private var exportTeam = false
    @State private var exportCaptin = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:12) {
                    HStack(spacing:12) {
                        Image(systemName:"soccerball.circle.fill").font(.system(size:48)).foregroundStyle(.cyan)
                        VStack(alignment:.leading,spacing:2) {
                            Text("Captain Tsubasa J").font(.title.bold())
                            Text("Modern Tool v42 — iOS").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    GroupBox("ملفات اللعبة") { VStack(spacing:10) {
                        Button { importTeam=true } label: { Label("استيراد TEAMDAT", systemImage:"person.3.fill").frame(maxWidth:.infinity) }.buttonStyle(.borderedProminent)
                        Button { importCaptin=true } label: { Label("استيراد CAPTIN.EXE", systemImage:"scope").frame(maxWidth:.infinity) }.buttonStyle(.bordered)
                        if !model.teamDataName.isEmpty { Text(model.teamDataName).font(.caption).foregroundStyle(.secondary) }
                        if !model.captinName.isEmpty { Text(model.captinName).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical,4) }
                    GroupBox("PS1 BIN") {
                        Text("افتح CTJ.bin من تبويب PS1 BIN. بعدها تستطيع رؤية ملفات اللعبة وصور اللاعبين مباشرة.")
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.padding(.horizontal,16).padding(.top,8).padding(.bottom,20)
            }
            .navigationTitle("CTJ v42").navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(isPresented:$importTeam, allowedContentTypes:[.item]) { if case .success(let u)=$0 { model.importTEAMDAT(url:u) } }
        .fileImporter(isPresented:$importCaptin, allowedContentTypes:[.item]) { if case .success(let u)=$0 { model.importCAPTIN(url:u) } }
        .fileExporter(isPresented:$exportTeam, document:DataDocument(data:model.teamData), contentType:.data, defaultFilename:"TEAMDAT_iOS_MOD.bin") {_ in}
        .fileExporter(isPresented:$exportCaptin, document:DataDocument(data:model.captinData), contentType:.data, defaultFilename:"CAPTIN_iOS_MOD.EXE") {_ in}
    }
}

struct DiscToolsView: View {
    @EnvironmentObject var model: CTJModel
    @State private var importDisc = false
    @State private var exportDisc = false
    @State private var search = ""
    var visibleFiles: [PSXDiscFile] {
        let all = model.discFiles.filter { !$0.isDirectory }
        if search.isEmpty { return all }
        return all.filter { $0.path.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:8) {
                if model.discData.isEmpty {
                    Spacer(minLength:20)
                    Image(systemName:"opticaldisc.fill").font(.system(size:64)).foregroundStyle(.cyan)
                    Text("افتح صورة لعبة PS1").font(.title2.bold())
                    Text("BIN 2352 أو ISO 2048").foregroundStyle(.secondary)
                    Button("اختيار BIN / ISO من Files") { importDisc = true }.buttonStyle(.borderedProminent).controlSize(.large)
                    Text("تم توسيع اختيار الملفات حتى يظهر CTJ.bin الموجود داخل مجلد Gamma.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    Spacer()
                } else {
                    HStack {
                        VStack(alignment:.leading) {
                            Text(model.discName).font(.headline)
                            Text("\(model.discFileCount) ملف داخل القرص").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Button("تغيير") { importDisc = true }.buttonStyle(.bordered)
                    }.padding(.horizontal)
                    List {
                        Section("ملفات اللعبة") {
                            ForEach(visibleFiles) { file in
                                VStack(alignment:.leading,spacing:5) {
                                    Text(file.path).font(.subheadline.monospaced()).lineLimit(1)
                                    Text("LBA \(file.lba) • \(file.size) bytes").font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        Button("فتح") { model.loadDiscFileIntoEditor(path:file.path) }.buttonStyle(.bordered)
                                        Button("حقن المعدل") { model.writeCurrentEditorFileBack(path:file.path) }.buttonStyle(.borderedProminent)
                                    }
                                }.padding(.vertical,2)
                            }
                        }
                    }.searchable(text:$search,prompt:"TEAM / CAPTIN / TEAMDAT")
                    Button("تصدير BIN المعدل") { exportDisc=true }.buttonStyle(.borderedProminent).padding(.bottom,6)
                }
            }.navigationTitle("PS1 BIN").navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(isPresented:$importDisc, allowedContentTypes:[.item], allowsMultipleSelection:false) { result in
            switch result { case .success(let u): model.importDisc(url:u); case .failure(let e): model.status="اختيار الملف فشل: \(e.localizedDescription)" }
        }
        .fileExporter(isPresented:$exportDisc, document:DataDocument(data:model.discData), contentType:.data, defaultFilename:patchedDiscName) {_ in}
    }
    var patchedDiscName:String { guard !model.discName.isEmpty else{return "CTJ_PATCHED.bin"}; let ns=model.discName as NSString; let ext=ns.pathExtension.isEmpty ? "bin":ns.pathExtension; return ns.deletingPathExtension+"_iOS_PATCHED."+ext }
}

struct PlayerEditorView: View {
    @EnvironmentObject var model: CTJModel
    @State private var bytes:[UInt8] = Array(repeating:0,count:16)
    @State private var portrait: UIImage?
    var body: some View {
        NavigationStack {
            Form {
                Section("صورة اللاعب") {
                    HStack(spacing:16) {
                        Group {
                            if let portrait { Image(uiImage:portrait).resizable().interpolation(.none).scaledToFit() }
                            else { ZStack { RoundedRectangle(cornerRadius:12).fill(.gray.opacity(0.15)); Image(systemName:"person.crop.square").font(.system(size:44)).foregroundStyle(.secondary) } }
                        }.frame(width:120,height:120).background(.black).clipShape(RoundedRectangle(cornerRadius:12))
                        VStack(alignment:.leading,spacing:8) {
                            Picker("الفريق",selection:$model.selectedTeam) { ForEach(0..<0x2D,id:\.self){ Text(String(format:"TEAM %02X",$0)).tag($0) } }
                            Stepper("اللاعب: \(model.selectedPlayer)",value:$model.selectedPlayer,in:0...31)
                            Button("تحديث الصورة") { refreshPortrait() }.buttonStyle(.borderedProminent)
                        }
                    }
                    if model.discData.isEmpty { Text("افتح CTJ.bin أولًا من تبويب PS1 BIN لقراءة صور TEAMxx.BIN.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("إحصائيات اللاعب") {
                    Button("تحميل السجل") { bytes=model.playerRecord(model.selectedPlayer) }
                    stat("Player ID",0,0...255); stat("Shirt",1,0...30)
                    Picker("Position",selection:Binding(get:{Int(bytes[2])},set:{bytes[2]=UInt8($0)})){ Text("FW").tag(0);Text("MF").tag(1);Text("DF").tag(2);Text("GK").tag(3) }
                    stat("Level",4,0...255); stat("Stamina",5,0...255); stat("Mobility",6,0...255); stat("Attack",7,0...255); stat("Technique",8,0...255); stat("Judgment",9,0...255); stat("Spirit",10,0...255)
                }
                Section("Raw 16 bytes") { ForEach(0..<16,id:\.self){ i in stat(String(format:"B%02d",i),i,0...255) } }
                Button("💾 حفظ تعديل اللاعب") { model.savePlayer(model.selectedPlayer,bytes:bytes) }.disabled(model.teamData.isEmpty)
            }
            .navigationTitle("Player Editor").navigationBarTitleDisplayMode(.inline)
            .onAppear { bytes=model.playerRecord(model.selectedPlayer); refreshPortrait() }
            .onChange(of:model.selectedPlayer){_,_ in bytes=model.playerRecord(model.selectedPlayer); refreshPortrait()}
            .onChange(of:model.selectedTeam){_,_ in refreshPortrait()}
            .onChange(of:model.discName){_,_ in refreshPortrait()}
        }
    }
    func refreshPortrait(){ portrait=model.playerPortrait(team:model.selectedTeam,player:model.selectedPlayer) }
    @ViewBuilder func stat(_ name:String,_ i:Int,_ range:ClosedRange<Int>)->some View { Stepper("\(name): \(bytes[i])",value:Binding(get:{Int(bytes[i])},set:{bytes[i]=UInt8(clamping:$0)}),in:range) }
}

struct ShotEditorView: View {
    @EnvironmentObject var model: CTJModel
    @State private var source:ShotRecord?; @State private var target:ShotRecord?; @State private var mode:ShotMode = .copy
    var unique:[ShotRecord]{var seen=Set<String>();return model.shots.sorted{$0.offset<$1.offset}.filter{seen.insert("\($0.playerID)-\($0.shotSlot)").inserted}}
    var body:some View{NavigationStack{VStack{if model.captinData.isEmpty{ContentUnavailableView("استورد CAPTIN.EXE أولاً",systemImage:"doc.badge.plus")}else{List{Section("العملية"){Picker("Mode",selection:$mode){ForEach(ShotMode.allCases,id:\.self){Text($0.title).tag($0)}};Text("Source: \(desc(source))");Text("Target: \(desc(target))");Button("تطبيق العملية"){if let s=source,let t=target{model.patchShot(source:s,target:t,mode:mode)}}.disabled(source==nil||target==nil)};Section("التسديدات"){ForEach(unique){r in HStack{VStack(alignment:.leading){Text(String(format:"ID %02X • Shot %02X",r.playerID,r.shotSlot)).font(.headline);Text(String(format:"Offset 0x%05X",r.offset)).font(.caption).foregroundStyle(.secondary)};Spacer();Button("S"){source=r}.buttonStyle(.bordered);Button("T"){target=r}.buttonStyle(.borderedProminent)}}}}}}.navigationTitle("Shot Editor").navigationBarTitleDisplayMode(.inline)}}
    func desc(_ r:ShotRecord?)->String{guard let r else{return "—"};return String(format:"ID %02X / slot %02X",r.playerID,r.shotSlot)}
}

struct TeamLogosView:View{let columns=[GridItem(.adaptive(minimum:82),spacing:12)];var body:some View{NavigationStack{ScrollView{LazyVGrid(columns:columns,spacing:16){ForEach(0..<0x2D,id:\.self){i in VStack{Image(String(format:"%02X",i)).interpolation(.none).resizable().scaledToFit().frame(width:72,height:60).background(.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius:10));Text("TEAM \(String(format:"%02X",i))").font(.caption.bold())}}}.padding()}.navigationTitle("Team Logos 00–2C").navigationBarTitleDisplayMode(.inline)}}