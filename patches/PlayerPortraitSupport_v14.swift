import UIKit

extension CTJModel {
    func playerPortrait(team:Int, player:Int) -> UIImage? {
        guard let reader = LargeDiscStore.reader else { return nil }
        do {
            let wanted = String(format:"TEAM%02X.BIN",team)
            guard let file = reader.files.first(where:{ !$0.isDirectory && $0.name.uppercased()==wanted }) else { return nil }
            let teamBytes = [UInt8](try reader.readFile(file, maxSize: 32 * 1024 * 1024))
            guard let top = CTJPortraitDecoder.offsetTable(teamBytes), !top.isEmpty,
                  let players = CTJPortraitDecoder.offsetTable(top[0]), player >= 0, player < players.count,
                  let expressions = CTJPortraitDecoder.offsetTable(players[player]), let first = expressions.first,
                  let raw = try? CTJPortraitDecoder.decompress(first), raw.count == 832 else { return nil }
            return CTJPortraitDecoder.image(raw)
        } catch { return nil }
    }
}

enum CTJPortraitDecoder {
    static func u32(_ d:[UInt8],_ p:Int)->Int { guard p>=0,p+3<d.count else{return -1}; return Int(d[p]) | Int(d[p+1])<<8 | Int(d[p+2])<<16 | Int(d[p+3])<<24 }
    static func offsetTable(_ d:[UInt8]) -> [[UInt8]]? {
        guard d.count >= 8 else{return nil}; let count=u32(d,0); guard count>0,count<=1000,4+count*4<=d.count else{return nil}
        var offs=[Int](); for i in 0..<count { let o=u32(d,4+i*4); guard o>=0,o<=d.count else{return nil}; offs.append(o) }
        var uniq=Array(Set(offs)).sorted(); guard !uniq.isEmpty else{return nil}; if uniq.last != d.count { uniq.append(d.count) }
        var out=[[UInt8]](); for i in 0..<(uniq.count-1) where uniq[i] <= uniq[i+1] { out.append(Array(d[uniq[i]..<uniq[i+1]])) }; return out
    }
    static func decompress(_ src:[UInt8]) throws -> [UInt8] {
        guard src.count>=5 else{throw NSError(domain:"CTJ",code:1)}; let target=(Int(src[2])<<8|Int(src[3]))+1; guard target>0,target<=2_000_000 else{throw NSError(domain:"CTJ",code:5)}
        var out=[UInt8](); out.reserveCapacity(target); var pos=4
        while out.count<target { guard pos<src.count else{throw NSError(domain:"CTJ",code:2)}; var flags=src[pos];pos+=1
            for _ in 0..<8 { if out.count>=target{break}; guard pos<src.count else{throw NSError(domain:"CTJ",code:3)}; let b1=src[pos];pos+=1
                if flags&1 != 0 { out.append(b1) } else { guard pos<src.count else{throw NSError(domain:"CTJ",code:4)}; let b2=src[pos];pos+=1; let length=Int(b1&0x0F)+3; let distance=Int(b1>>4)|(Int(b2)<<4); guard distance>0,distance<=out.count else{throw NSError(domain:"CTJ",code:6)}; var sp=out.count-distance; for _ in 0..<length { if out.count>=target{break}; guard sp>=0,sp<out.count else{throw NSError(domain:"CTJ",code:7)}; out.append(out[sp]);sp+=1 } }
                flags >>= 1
            }
        }; return out
    }
    static func image(_ d:[UInt8]) -> UIImage? {
        guard d.count==832 else{return nil}; var pal=[(UInt8,UInt8,UInt8)](); for i in 0..<16 { let v=UInt16(d[i*2])|UInt16(d[i*2+1])<<8; pal.append((UInt8(v&31)*8,UInt8((v>>5)&31)*8,UInt8((v>>10)&31)*8)) }
        var rgba=[UInt8]();rgba.reserveCapacity(40*40*4); for b in d[32...] { for idx in [Int(b&0x0F),Int((b>>4)&0x0F)] { let c=pal[idx];rgba.append(c.0);rgba.append(c.1);rgba.append(c.2);rgba.append(idx==0 ? 0:255) } }
        let data=Data(rgba); guard let provider=CGDataProvider(data:data as CFData), let cg=CGImage(width:40,height:40,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:160,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else{return nil}; return UIImage(cgImage:cg)
    }
}
