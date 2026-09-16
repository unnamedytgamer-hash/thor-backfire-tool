#!/usr/bin/env bash
set -e
python3 - <<'PYCODE'
from pathlib import Path
p=Path('app/src/main/java/com/openai/thorbackfire/MainActivity.java')
s=p.read_text()

s=s.replace('import android.content.pm.PackageManager;','''import android.content.pm.PackageManager;
import android.content.ContentValues;
import android.net.Uri;
import android.provider.MediaStore;''')
s=s.replace('import java.io.ByteArrayOutputStream;','''import java.io.ByteArrayOutputStream;
import java.io.OutputStream;''')
s=s.replace('import java.util.*;','''import java.util.*;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;''')

s=s.replace('Button connect,disconnect,read,set3,set4,set5,set7;','Button connect,disconnect,read,set3,set4,set5,set7,dumpRules;')
s=s.replace('''    boolean pendingSetRejected=false;
    final Handler h=''','''    boolean pendingSetRejected=false;
    ByteArrayOutputStream dumpOut;
    int dumpType=0,dumpSize=0,dumpOffset=0,dumpChunk=200;
    boolean dumpBoth=false;
    byte[] dumpedRls,dumpedRlm;
    final Handler h=''')

s=s.replace('''        set7.setOnClickListener(v->sendSet(7));''','''        set7.setOnClickListener(v->sendSet(7));
        dumpRules.setOnClickListener(v->startDumpBoth());''')

s=s.replace('''        read=btn("Leer valor actual"); read.setEnabled(false); root.addView(read);''','''        read=btn("Leer valor actual"); read.setEnabled(false); root.addView(read);
        dumpRules=btn("EXTRAER REGLAS S63 (RLS2 + RLM2)"); dumpRules.setEnabled(false); root.addView(dumpRules);''')

s=s.replace('''title.setText("THOR Backfire Tool v6")''','''title.setText("THOR Backfire Tool v7 · Rule Dumper")''')
s=s.replace('''set3.setEnabled(on);set4.setEnabled(on);set5.setEnabled(on);set7.setEnabled(on);''','''set3.setEnabled(on);set4.setEnabled(on);set5.setEnabled(on);set7.setEnabled(on);dumpRules.setEnabled(on);''')

needle='''                case "set":\n'''
insert='''                case "dump_start": {
                    if((cmd & 0x8000)!=0){
                        int ec=(msg!=null && msg.length>=4)?u16at(msg,2):-1;
                        uiStatus("THOR rechazó extracción tipo "+dumpType+" · 0x"+hx(ec));
                        log("DUMP start rechazado tipo="+dumpType+" code=0x"+hx(ec));
                        dumpBoth=false; step="idle"; break;
                    }
                    if(msg==null || msg.length<8){ uiStatus("Respuesta de extracción inválida"); step="idle"; dumpBoth=false; break; }
                    dumpSize=u32at(msg,2);
                    int accepted=u16at(msg,6);
                    if(accepted>0) dumpChunk=Math.min(200,accepted); else dumpChunk=200;
                    dumpOffset=0; dumpOut=new ByteArrayOutputStream(Math.max(0,dumpSize));
                    log("DUMP tipo="+dumpType+" tamaño="+dumpSize+" bloque="+dumpChunk);
                    uiStatus("Extrayendo "+(dumpType==5?"RLS2":"RLM2")+" · 0/"+dumpSize+" bytes…");
                    step="dump_block"; sendDumpBlock(); break;
                }
                case "dump_block": {
                    if((cmd & 0x8000)!=0){
                        int ec=(msg!=null && msg.length>=4)?u16at(msg,2):-1;
                        uiStatus("Error leyendo reglas · 0x"+hx(ec)); log("DUMP block error 0x"+hx(ec)); dumpBoth=false; step="idle"; break;
                    }
                    if(msg==null || msg.length<4){ uiStatus("Bloque de reglas inválido"); dumpBoth=false; step="idle"; break; }
                    int n=u16at(msg,2);
                    if(n<0 || msg.length<4+n){ uiStatus("Longitud de bloque inválida"); dumpBoth=false; step="idle"; break; }
                    if(n>0) dumpOut.write(msg,4,n);
                    dumpOffset+=n;
                    uiStatus("Extrayendo "+(dumpType==5?"RLS2":"RLM2")+" · "+dumpOffset+"/"+dumpSize+" bytes…");
                    if(n==0 || dumpOffset>=dumpSize){
                        step="dump_stop"; waitFor(1,0x0082); sendEncrypted(logical(0x0082,new byte[0]));
                    } else sendDumpBlock();
                    break;
                }
                case "dump_stop": {
                    if((cmd & 0x8000)!=0){ uiStatus("Error cerrando extracción"); dumpBoth=false; step="idle"; break; }
                    byte[] data=dumpOut==null?new byte[0]:dumpOut.toByteArray();
                    saveDumpFile(dumpType,data);
                    if(dumpType==5 && dumpBoth){ startDump(6); }
                    else {
                        dumpBoth=false; step="idle";
                        if(dumpedRls!=null && dumpedRlm!=null){ saveBundleZip(); uiStatus("EXTRACCIÓN COMPLETA · ZIP guardado en Descargas"); }
                        else uiStatus("Extracción terminada");
                    }
                    break;
                }
                case "set":
'''
if needle not in s: raise SystemExit('case set marker missing')
s=s.replace(needle,insert,1)

marker='''    @SuppressWarnings("MissingPermission") void sendRaw(int type,byte[] payload){'''
methods=r'''    void startDumpBoth(){
        if(ctr==null){uiStatus("Conecta primero al THOR");return;}
        dumpedRls=null; dumpedRlm=null; dumpBoth=true; startDump(5);
    }
    void startDump(int type){
        if(ctr==null)return;
        try{
            dumpType=type; dumpSize=0; dumpOffset=0; dumpChunk=200; dumpOut=null;
            byte[] fileId=new byte[]{(byte)type,(byte)(PKG>>>8),(byte)PKG,(byte)VER};
            step="dump_start"; waitFor(1,0x0080);
            uiStatus("Abriendo "+(type==5?"RLS2":"RLM2")+" del S63…");
            log("DUMP start fileId="+hex(fileId));
            sendEncrypted(logical(0x0080,cat(fileId,u16(200))));
        }catch(Exception e){fail(e);dumpBoth=false;step="idle";}
    }
    void sendDumpBlock() throws Exception {
        waitFor(1,0x0081);
        sendEncrypted(logical(0x0081,u32(dumpOffset)));
    }
    void saveDumpFile(int type,byte[] data) throws Exception {
        String expected=type==5?"RLS2":"RLM2";
        String magic=data.length>=4?new String(data,0,4,java.nio.charset.StandardCharsets.US_ASCII):"";
        boolean crcOk=false;
        if(data.length>=2){int got=(data[data.length-2]&255)|((data[data.length-1]&255)<<8);int calc=crc16(Arrays.copyOf(data,data.length-2));crcOk=got==calc;}
        String ext=type==5?"smprl":"pkgrl";
        String name="THOR_S63_"+expected+"_001F_v5."+ext;
        saveToDownloads(name,data,"application/octet-stream");
        if(type==5)dumpedRls=data;else dumpedRlm=data;
        log("Guardado "+name+" bytes="+data.length+" magic="+magic+" crc="+(crcOk?"OK":"NO"));
        if(!expected.equals(magic)) log("AVISO: magic esperado "+expected+" pero llegó "+magic);
    }
    void saveBundleZip() throws Exception {
        ByteArrayOutputStream bos=new ByteArrayOutputStream();
        try(ZipOutputStream zos=new ZipOutputStream(bos)){
            ZipEntry e1=new ZipEntry("THOR_S63_RLS2_001F_v5.smprl");zos.putNextEntry(e1);zos.write(dumpedRls);zos.closeEntry();
            ZipEntry e2=new ZipEntry("THOR_S63_RLM2_001F_v5.pkgrl");zos.putNextEntry(e2);zos.write(dumpedRlm);zos.closeEntry();
        }
        saveToDownloads("THOR_S63_RULES_001F_v5.zip",bos.toByteArray(),"application/zip");
        log("ZIP guardado: THOR_S63_RULES_001F_v5.zip");
    }
    void saveToDownloads(String name,byte[] data,String mime) throws Exception {
        if(Build.VERSION.SDK_INT<29)throw new Exception("Se requiere Android 10+ para guardar en Descargas");
        ContentValues cv=new ContentValues();
        cv.put(MediaStore.MediaColumns.DISPLAY_NAME,name);
        cv.put(MediaStore.MediaColumns.MIME_TYPE,mime);
        cv.put(MediaStore.MediaColumns.RELATIVE_PATH,Environment.DIRECTORY_DOWNLOADS);
        Uri uri=getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,cv);
        if(uri==null)throw new Exception("No se pudo crear "+name);
        try(OutputStream os=getContentResolver().openOutputStream(uri)){if(os==null)throw new Exception("No se pudo abrir "+name);os.write(data);}
    }

'''
if marker not in s: raise SystemExit('sendRaw marker missing')
s=s.replace(marker,methods+marker,1)

# add u32 helpers next to u16 helpers
old='''static byte[] logical(int cmd,byte[] body){return cat(u16(cmd),body);} static byte[] u16(int v){return new byte[]{(byte)(v>>>8),(byte)v};} static int u16at(byte[] a,int i){return ((a[i]&255)<<8)|(a[i+1]&255);}'''
new='''static byte[] logical(int cmd,byte[] body){return cat(u16(cmd),body);} static byte[] u16(int v){return new byte[]{(byte)(v>>>8),(byte)v};} static int u16at(byte[] a,int i){return ((a[i]&255)<<8)|(a[i+1]&255);} static byte[] u32(int v){return new byte[]{(byte)(v>>>24),(byte)(v>>>16),(byte)(v>>>8),(byte)v};} static int u32at(byte[] a,int i){return ((a[i]&255)<<24)|((a[i+1]&255)<<16)|((a[i+2]&255)<<8)|(a[i+3]&255);}'''
if old not in s: raise SystemExit('helper marker missing')
s=s.replace(old,new,1)

p.write_text(s)
print('patched',len(s))

PYCODE
# Public demo metadata attempt; no account credentials are used.
curl -L -sS --max-time 20 -X POST -H 'Content-Type: application/x-www-form-urlencoded' --data 'id_sound_pkg=31&language=en' 'https://sec2.thor-tuning.com/api/shop/get-demo-sound-pack' -o thor_demo_sound_31.json || true
if [ -s thor_demo_sound_31.json ]; then git add thor_demo_sound_31.json; fi
git add app/src/main/java/com/openai/thorbackfire/MainActivity.java
git commit -m 'Add S63 sound rule dumper'
git push
