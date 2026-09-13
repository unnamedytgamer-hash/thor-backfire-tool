package com.openai.thorbackfire;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.pm.PackageManager;
import android.os.*;
import android.text.method.ScrollingMovementMethod;
import android.view.View;
import android.widget.*;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.SecureRandom;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

public class MainActivity extends Activity {
    private static final UUID SERVICE_NORDIC = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
    private static final UUID CHAR_WRITE_NORDIC = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e");
    private static final UUID CHAR_NOTIFY_NORDIC = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e");
    private static final UUID SERVICE_STANDARD = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb");
    private static final UUID CHAR_STANDARD = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb");
    private static final UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final int PKG=0x001f, VER=0x0005, MODE=0x0003, RULE=0x0021;
    private static final int REQ=1001;

    TextView status,current,logView;
    Button connect,disconnect,read,set3,set7;
    BluetoothAdapter adapter; BluetoothLeScanner scanner; BluetoothGatt gatt;
    BluetoothGattCharacteristic writeChar, notifyChar;
    byte[] rxBuf=new byte[0], key, ctr;
    int pendingType=-1, pendingCmd=-1;
    String step="idle";
    int warmIndex=0, pendingSetValue=-1;
    final Handler h=new Handler(Looper.getMainLooper());

    @Override public void onCreate(Bundle b){ super.onCreate(b); buildUi();
        BluetoothManager bm=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE); adapter=bm.getAdapter();
        connect.setOnClickListener(v->ensurePermsAndScan()); disconnect.setOnClickListener(v->disconnectNow());
        read.setOnClickListener(v->{ if(gatt!=null) sendRead(); });
        set3.setOnClickListener(v->sendSet(3)); set7.setOnClickListener(v->sendSet(7));
    }

    void buildUi(){
        LinearLayout root=new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setPadding(28,28,28,28);
        TextView title=new TextView(this); title.setText("THOR Backfire Tool"); title.setTextSize(28); root.addView(title);
        TextView sub=new TextView(this); sub.setText("Herramienta experimental para leer/escribir la regla de pops del THOR. Mantén cerrada la app THOR oficial mientras esté conectada."); sub.setTextSize(16); root.addView(sub);
        status=new TextView(this); status.setText("Sin conectar"); status.setTextSize(18); status.setPadding(0,24,0,8); root.addView(status);
        connect=btn("Conectar al THOR"); root.addView(connect); disconnect=btn("Desconectar"); disconnect.setEnabled(false); root.addView(disconnect);
        TextView preset=new TextView(this); preset.setText("\nPreset: packageId=0x001F · versionId=0x0005 · modeTypeId=0x0003 · regla=0x0021"); preset.setTextSize(15); root.addView(preset);
        current=new TextView(this); current.setText("Valor actual: —"); current.setTextSize(20); current.setPadding(0,16,0,8); root.addView(current);
        LinearLayout row=new LinearLayout(this); row.setOrientation(LinearLayout.HORIZONTAL);
        set3=btn("Aplicar 3"); set7=btn("Aplicar 7"); set3.setEnabled(false); set7.setEnabled(false);
        row.addView(set3,new LinearLayout.LayoutParams(0,-2,1)); row.addView(set7,new LinearLayout.LayoutParams(0,-2,1)); root.addView(row);
        read=btn("Leer valor actual"); read.setEnabled(false); root.addView(read);
        TextView lh=new TextView(this); lh.setText("\nRegistro"); lh.setTextSize(18); root.addView(lh);
        logView=new TextView(this); logView.setTextSize(12); logView.setMovementMethod(new ScrollingMovementMethod());
        ScrollView sv=new ScrollView(this); sv.addView(logView); root.addView(sv,new LinearLayout.LayoutParams(-1,0,1));
        setContentView(root);
    }
    Button btn(String s){ Button b=new Button(this); b.setText(s); return b; }
    void uiStatus(String s){ runOnUiThread(()->status.setText(s)); }
    void log(String s){ runOnUiThread(()->{ logView.append("["+new java.text.SimpleDateFormat("HH:mm:ss",Locale.getDefault()).format(new Date())+"] "+s+"\n"); }); }
    void enable(boolean on){ runOnUiThread(()->{connect.setEnabled(!on);disconnect.setEnabled(on);read.setEnabled(on);set3.setEnabled(on);set7.setEnabled(on);}); }

    void ensurePermsAndScan(){
        if(Build.VERSION.SDK_INT>=31){
            ArrayList<String> need=new ArrayList<>();
            if(checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)!=PackageManager.PERMISSION_GRANTED) need.add(Manifest.permission.BLUETOOTH_SCAN);
            if(checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)!=PackageManager.PERMISSION_GRANTED) need.add(Manifest.permission.BLUETOOTH_CONNECT);
            if(!need.isEmpty()){ requestPermissions(need.toArray(new String[0]),REQ); return; }
        } else if(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED){ requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION},REQ); return; }
        startScan();
    }
    @Override public void onRequestPermissionsResult(int r,String[] p,int[] g){ super.onRequestPermissionsResult(r,p,g); if(r==REQ){ boolean ok=true;for(int x:g)if(x!=PackageManager.PERMISSION_GRANTED)ok=false; if(ok)startScan(); else uiStatus("Permiso Bluetooth denegado"); } }

    @SuppressWarnings("MissingPermission") void startScan(){
        if(adapter==null||!adapter.isEnabled()){ uiStatus("Activa Bluetooth primero"); return; }
        scanner=adapter.getBluetoothLeScanner(); if(scanner==null){uiStatus("No hay escáner BLE");return;}
        uiStatus("Buscando THOR…"); log("Escaneo BLE iniciado");
        scanner.startScan(scanCb); h.postDelayed(()->{ try{scanner.stopScan(scanCb);}catch(Exception ignored){} if(gatt==null)uiStatus("No encontré THOR. Comprueba que esté encendido."); },12000);
    }
    final ScanCallback scanCb=new ScanCallback(){ @SuppressWarnings("MissingPermission") @Override public void onScanResult(int t,ScanResult r){
        ScanRecord sr=r.getScanRecord(); boolean match=false;
        if(sr!=null && sr.getServiceUuids()!=null) for(android.os.ParcelUuid u:sr.getServiceUuids()) if(SERVICE_NORDIC.equals(u.getUuid()) || SERVICE_STANDARD.equals(u.getUuid())) match=true;
        String n=r.getDevice().getName(); if(n!=null && n.toLowerCase(Locale.ROOT).contains("thor")) match=true;
        if(match){ try{scanner.stopScan(this);}catch(Exception ignored){} uiStatus("Conectando a "+(n==null?"THOR":n)+"…"); log("Dispositivo encontrado: "+n+" "+r.getDevice().getAddress()); gatt=r.getDevice().connectGatt(MainActivity.this,false,gattCb,BluetoothDevice.TRANSPORT_LE); }
    }};

    final BluetoothGattCallback gattCb=new BluetoothGattCallback(){
        @Override public void onConnectionStateChange(BluetoothGatt g,int st,int ns){ if(ns==BluetoothProfile.STATE_CONNECTED){log("GATT conectado"); uiStatus("Descubriendo servicio…"); g.discoverServices();} else {log("GATT desconectado status="+st); uiStatus("Desconectado"); enable(false);} }
        @Override public void onServicesDiscovered(BluetoothGatt g,int st){
            BluetoothGattService s=g.getService(SERVICE_NORDIC);
            boolean nordic=s!=null;
            if(!nordic) s=g.getService(SERVICE_STANDARD);
            if(s==null){uiStatus("Servicio THOR BLE no encontrado");return;}
            writeChar=null; notifyChar=null;
            for(BluetoothGattCharacteristic c:s.getCharacteristics()){
                UUID u=c.getUuid(); int p=c.getProperties();
                if(nordic){
                    if(CHAR_WRITE_NORDIC.equals(u)) writeChar=c;
                    if(CHAR_NOTIFY_NORDIC.equals(u)) notifyChar=c;
                } else if(CHAR_STANDARD.equals(u)){
                    if((p&(BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE|BluetoothGattCharacteristic.PROPERTY_WRITE))!=0 && writeChar==null)writeChar=c;
                    if((p&(BluetoothGattCharacteristic.PROPERTY_NOTIFY|BluetoothGattCharacteristic.PROPERTY_INDICATE))!=0 && notifyChar==null)notifyChar=c;
                }
            }
            if(writeChar==null||notifyChar==null){uiStatus("Características THOR incompatibles"); log("write="+writeChar+" notify="+notifyChar);return;}
            log("Características listas: "+(nordic?"Nordic UART":"FFE0/FFE1"));
            g.setCharacteristicNotification(notifyChar,true); BluetoothGattDescriptor d=notifyChar.getDescriptor(CCCD);
            if(d==null){uiStatus("CCCD no encontrado");return;} d.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE); g.writeDescriptor(d);
        }
        @Override public void onDescriptorWrite(BluetoothGatt g,BluetoothGattDescriptor d,int st){ if(CCCD.equals(d.getUuid())){log("Notificaciones activadas"); step="hardware"; waitFor(0,-1); sendRaw(0,u16(1));} }
        @Override public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c){ onRx(c.getValue()); }
    };

    void onRx(byte[] a){ rxBuf=cat(rxBuf,a); while(rxBuf.length>=6){ int i=0;while(i+1<rxBuf.length&&(rxBuf[i]!=(byte)0xa5||rxBuf[i+1]!=0x5a))i++; if(i>0)rxBuf=Arrays.copyOfRange(rxBuf,i,rxBuf.length); if(rxBuf.length<6)return; int sw=((rxBuf[2]&255)<<8)|(rxBuf[3]&255), n=sw&0x1fff, total=4+n+2; if(rxBuf.length<total)return; byte[] f=Arrays.copyOfRange(rxBuf,0,total);rxBuf=Arrays.copyOfRange(rxBuf,total,rxBuf.length); parseFrame(f); } }
    void parseFrame(byte[] f){ try{ int sw=((f[2]&255)<<8)|(f[3]&255),type=sw>>>13,n=sw&0x1fff; byte[] p=Arrays.copyOfRange(f,4,4+n);int got=(f[4+n]&255)|((f[5+n]&255)<<8),calc=crc16(Arrays.copyOfRange(f,0,4+n)); if(got!=calc){log("CRC RX incorrecto");return;}
        if(type==1){ byte[] pt=crypt(p); int pad=pt[0]&255; if(pad<1||pad>=pt.length){log("Padding cifrado inválido");return;} byte[] msg=Arrays.copyOfRange(pt,1,pt.length-pad); int cmd=msg.length>=2?u16at(msg,0):-1; log("RX cifrado cmd=0x"+hx(cmd)); handleResponse(type,cmd,msg,p); }
        else { log("RX type="+type+" "+hex(p)); handleResponse(type,-1,null,p); }
    }catch(Exception e){fail(e);} }
    void waitFor(int type,int cmd){pendingType=type;pendingCmd=cmd;}
    void handleResponse(int type,int cmd,byte[] msg,byte[] payload){ if(type!=pendingType)return; if(type==1&&cmd!=pendingCmd)return; pendingType=-1;pendingCmd=-1;
        try{
            switch(step){
                case "hardware": if(payload.length<8||payload[0]!=0||payload[1]!=1){fail(new Exception("Respuesta hardware inesperada"));return;} int sn=u16at(payload,2),fw=u16at(payload,4),hw=u16at(payload,6); key=deriveKey(hw,fw,sn); byte[] ivh=new byte[8];new SecureRandom().nextBytes(ivh); tempIvHost=ivh; log("HW serial="+sn+" fw=0x"+hx(fw)+" hw=0x"+hx(hw)); step="iv";waitFor(2,-1);sendRaw(2,ivh);break;
                case "iv": if(payload.length!=8){fail(new Exception("IV del dispositivo inválido"));return;} ctr=cat(tempIvHost,payload); log("Handshake OK"); warmIndex=0;step="warm";sendWarm();break;
                case "warm": warmIndex++; if(warmIndex<5)sendWarm(); else {enable(true);uiStatus("Conectado. Leyendo valor…");sendRead();} break;
                case "read": int v=parseRule(msg,RULE); runOnUiThread(()->current.setText("Valor actual: "+(v<0?"no encontrado":v))); log("Regla 0x0021 = "+v); if(pendingSetValue>=0){ if(v==pendingSetValue)uiStatus("Confirmado por THOR: valor "+v); else uiStatus("Lectura posterior: "+v+" (se pidió "+pendingSetValue+")"); pendingSetValue=-1;} else uiStatus("Conectado"); step="idle"; break;
                case "set": log("Escritura aceptada; verificando…"); step="read"; sendReadInternal(); break;
            }
        }catch(Exception e){fail(e);}
    }
    byte[] tempIvHost;
    void sendWarm() throws Exception { byte[] msg; int cmd; switch(warmIndex){
        case 0:cmd=0x0080;msg=logical(cmd,new byte[]{8,0,0,0,0,(byte)0xf0});break;
        case 1:cmd=0x0081;msg=logical(cmd,new byte[]{0,0,0,0});break;
        case 2:cmd=0x0081;msg=logical(cmd,new byte[]{0,0,0,(byte)0xc8});break;
        case 3:cmd=0x0081;msg=logical(cmd,new byte[]{0,0,1,(byte)0x90});break;
        default:cmd=0x0082;msg=logical(cmd,new byte[0]);
    } waitFor(1,cmd); sendEncrypted(msg); }
    void sendRead(){ if(ctr==null)return; step="read";pendingSetValue=-1; try{sendReadInternal();}catch(Exception e){fail(e);} }
    void sendReadInternal() throws Exception { int cmd=0x0034;waitFor(1,cmd);sendEncrypted(logical(cmd,cat(u16(PKG),u16(MODE)))); }
    void sendSet(int v){ if(ctr==null)return; try{ int cmd=0x0043;byte[] body=cat(u16(PKG),u16(VER),u16(MODE),u16(1),u16(RULE),u16(v)); pendingSetValue=v;step="set";waitFor(1,cmd);uiStatus("Enviando valor "+v+"…");sendEncrypted(logical(cmd,body)); }catch(Exception e){fail(e);} }

    @SuppressWarnings("MissingPermission") void sendRaw(int type,byte[] payload){ try{ byte[] f=frame(type,payload); writeChar.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE); writeChar.setValue(f); boolean ok=gatt.writeCharacteristic(writeChar); log("TX type="+type+" "+hex(payload)+(ok?"":" [write=false]")); }catch(Exception e){fail(e);} }
    void sendEncrypted(byte[] msg) throws Exception { sendRaw(1,crypt(padded(msg))); }
    byte[] crypt(byte[] data) throws Exception { byte[] iv=Arrays.copyOf(ctr,16); Cipher c=Cipher.getInstance("AES/CTR/NoPadding"); c.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES"),new IvParameterSpec(iv)); byte[] out=c.doFinal(data); incCounter(ctr,(data.length+15)/16); return out; }

    static byte[] deriveKey(int hw,int fw,int sn){ long x=((long)hw*0x35L+(long)fw*0xf1L+(long)sn*0x0bL)&0xffffffffL; x=(x^((x>>>16)^(x>>>8)^(x>>>24)))&0xffffffffL; int lo8=(int)x&255,lo16=(int)x&65535;int[] c1={0x1a,0xb6,0x8f,0x0d,0xc3,0x5b,0x34,0x82},c2={0xf1,0x11,0x82,0x30,0x5b,0xed,0x4a,0x58};byte[] k=new byte[16];for(int i=0;i<8;i++)k[i]=(byte)((((lo8+c1[i])&255)^c2[i])&255);int[] add={0x27,0x41,0xa9,0x75},xor={0xe4,0,0x22,0,0x6a,0,0x40,0};byte[] vb=new byte[8];for(int j=0;j<4;j++){int z=(lo16+add[j])&65535;vb[j*2]=(byte)z;vb[j*2+1]=(byte)(z>>>8);}for(int i=0;i<8;i++)vb[i]^=(byte)xor[i];k[8]=vb[0];k[9]=vb[2];k[10]=vb[4];k[11]=vb[6];k[12]=(byte)(((x+0x4eL)^0x4cL)&255);k[13]=(byte)((x^0x35L)&255);k[14]=(byte)(((x-0x64L)^0xf4L)&255);k[15]=(byte)(((x+0x68L)^0xe5L)&255);return k;}
    static byte[] padded(byte[] msg){int p=16-((msg.length+1)%16);if(p==0)p=16;byte[] o=new byte[1+msg.length+p];o[0]=(byte)p;System.arraycopy(msg,0,o,1,msg.length);Arrays.fill(o,1+msg.length,o.length,(byte)0xa5);return o;}
    static byte[] logical(int cmd,byte[] body){return cat(u16(cmd),body);} static byte[] u16(int v){return new byte[]{(byte)(v>>>8),(byte)v};} static int u16at(byte[] a,int i){return ((a[i]&255)<<8)|(a[i+1]&255);} static String hx(int v){return String.format(Locale.ROOT,"%04x",v&0xffff);} static String hex(byte[] a){StringBuilder s=new StringBuilder();for(byte b:a)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}
    static byte[] cat(byte[]... aa){int n=0;for(byte[] a:aa)n+=a.length;byte[] o=new byte[n];int p=0;for(byte[] a:aa){System.arraycopy(a,0,o,p,a.length);p+=a.length;}return o;}
    static int crc16(byte[] a){int c=0xffff;for(byte bb:a){c^=bb&255;for(int i=0;i<8;i++)c=((c&1)!=0)?((c>>>1)^0xa001):(c>>>1);}return c&0xffff;}
    static byte[] frame(int type,byte[] p){int sw=((type&7)<<13)|(p.length&0x1fff);byte[] pre=cat(new byte[]{(byte)0xa5,0x5a,(byte)(sw>>>8),(byte)sw},p);int c=crc16(pre);return cat(pre,new byte[]{(byte)c,(byte)(c>>>8)});} static void incCounter(byte[] c,int blocks){long x=blocks;for(int i=15;i>=0&&x>0;i--){long s=(c[i]&255L)+(x&255L);c[i]=(byte)s;x=(x>>>8)+(s>>>8);}}
    static int parseRule(byte[] msg,int rule){ if(msg==null||msg.length<8)return -1;int count=u16at(msg,6),off=8;for(int n=0;n<count&&off+3<msg.length;n++,off+=4){int r=u16at(msg,off),v=u16at(msg,off+2);if(r==rule)return v;}return -1;}

    @SuppressWarnings("MissingPermission") void disconnectNow(){ try{ if(scanner!=null)scanner.stopScan(scanCb);}catch(Exception ignored){} if(gatt!=null){gatt.disconnect();gatt.close();gatt=null;} writeChar=notifyChar=null;key=ctr=null;step="idle";enable(false);uiStatus("Desconectado"); }
    void fail(Exception e){ log("ERROR: "+e.getMessage()); uiStatus("Error: "+e.getMessage()); }
    @Override protected void onDestroy(){ disconnectNow();super.onDestroy(); }
}
