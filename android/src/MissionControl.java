package local.nexusmission.monitor;

import android.app.Activity;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

public class MissionControl extends Activity {
    private static final int BG=0xff09101c, PANEL=0xff142339, LIGHT=0xffeff5ff, MUTED=0xffa7bbd1, CYAN=0xff6ee9fc;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final List<double[]> history = new ArrayList<>();
    private final TextView[] values = new TextView[6];
    private final LinearLayout[] screens = new LinearLayout[3];
    private final Button[] tabs = new Button[3];
    private LinearLayout root;
    private ScrollView scroll;
    private TextView status, detail, pc, settingsStatus;
    private EditText port, token, interval;
    private Button addressPicker;
    private TextView addressHint;
    private String selectedIP;
    private String[] addresses;
    private Button connect;
    private Trend chart;
    private SharedPreferences prefs;
    private boolean active;
    private int generation;


    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences("nexus", MODE_PRIVATE);
        addresses = getResources().getStringArray(R.array.pc_addresses);
        selectedIP = prefs.getString("host",addresses[0]);
        if (!Arrays.asList(addresses).contains(selectedIP)) selectedIP=addresses[0];
        root = column();
        root.setBackgroundColor(BG);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        setContentView(root);
        LinearLayout brand = new LinearLayout(this);
        brand.setGravity(Gravity.CENTER_VERTICAL);
        ImageView mark = new ImageView(this);
        mark.setImageResource(R.drawable.nexus);
        brand.addView(mark,new LinearLayout.LayoutParams(dp(32),dp(32)));
        TextView wordmark = label("NEXUS",17,LIGHT,true);
        wordmark.setLetterSpacing(.16f);
        wordmark.setPadding(dp(9),0,0,0);
        brand.addView(wordmark);
        root.addView(brand,rowParams(20,12));
        scroll = new ScrollView(this);
        root.addView(scroll, new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout nav = new LinearLayout(this);
        nav.setPadding(dp(12),dp(6),dp(12),dp(6)); nav.setBackgroundColor(0xff101c2a);
        root.addView(nav);
        String[] names = {"Dashboard","Devices","Settings"};
        for (int i=0; i<3; i++) {
            final int page = i;
            screens[i] = column();
            screens[i].setPadding(dp(20),dp(16),dp(20),dp(24));
            screens[i].addView(label(names[i],32,LIGHT,true));
            tabs[i] = button(names[i]);
            tabs[i].setTextSize(14);
            nav.addView(tabs[i],new LinearLayout.LayoutParams(0,-2,1));
            tabs[i].setOnClickListener(v -> show(page));
        }
        LinearLayout dashboard = screens[0];
        status = label("",18,CYAN,true);
        detail = label("",14,MUTED,false);
        LinearLayout connection = card(dashboard);
        connection.addView(status); connection.addView(detail);
        LinearLayout graph = card(dashboard);
        graph.addView(label("Resource history",18,LIGHT,true));
        LinearLayout legend = new LinearLayout(this);
        legend.addView(label("●  CPU     ",13,CYAN,true));
        legend.addView(label("●  RAM",13,0xffa9aaff,true));
        graph.addView(legend);
        chart = new Trend(this,history);
        graph.addView(chart,new LinearLayout.LayoutParams(-1,dp(112)));
        LinearLayout axis = new LinearLayout(this);
        axis.addView(label("60 seconds ago",12,MUTED,false),new LinearLayout.LayoutParams(0,-2,1));
        axis.addView(label("Now",12,MUTED,false)); graph.addView(axis);
        String[] metrics={"Processor","Memory","System disk","Uptime","Upload","Download"};
        for (int i=0; i<6; i+=2) {
            LinearLayout row = new LinearLayout(this);
            dashboard.addView(row);
            for (int j=i; j<i+2; j++) {
                LinearLayout tile = column();
                styleCard(tile);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,-2,1);
                lp.setMargins(j==i ? 0:dp(4),dp(8),j==i ? dp(4):0,0);
                row.addView(tile,lp);
                tile.addView(label(metrics[j],14,MUTED,false));
                values[j] = label("—",24,LIGHT,true); values[j].setFontFeatureSettings("tnum"); tile.addView(values[j]);
            }
        }
        LinearLayout machine = card(screens[1]);
        machine.addView(label("Windows PC",18,LIGHT,true));
        pc = label("",15,MUTED,false); machine.addView(pc);
        for (String name : new String[]{"ESP32","ESP32-CAM","3D printer"}) {
            LinearLayout device = card(screens[1]);
            device.addView(label(name,18,LIGHT,true)); device.addView(label("Future integration",14,MUTED,false));
        }
        LinearLayout settings = card(screens[2]);
        settings.addView(label("Server address",14,MUTED,false));
        addressPicker = button("");
        addressPicker.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        addressPicker.setPadding(dp(12),0,dp(12),0);
        addressPicker.setOnClickListener(v -> new android.app.AlertDialog.Builder(this)
            .setTitle("Server address").setSingleChoiceItems(addresses, Arrays.asList(addresses).indexOf(selectedIP), (dialog,index) -> {
                selectedIP=addresses[index]; token.setText(""); refreshAddress(); dialog.dismiss();
            }).setNegativeButton("Cancel",null).show());
        settings.addView(addressPicker,rowParams(0,6));
        addressHint=label("",13,MUTED,false);
        settings.addView(addressHint,rowParams(0,4)); refreshAddress();
        port = field(settings,"Port",prefs.getString("port","8765"),InputType.TYPE_CLASS_NUMBER);
        token = field(settings,"Pairing token","",InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD);
        token.setSaveEnabled(false);
        token.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        token.setHint("Leave blank to use saved token");
        interval = field(settings,"Refresh interval (2–30 seconds)",prefs.getString("interval","2"),InputType.TYPE_CLASS_NUMBER);
        connect = button("Connect"); settings.addView(connect,rowParams(0,16));
        connect.setOnClickListener(v -> { if (active) stop("Disconnected","Open Settings to connect."); else pair(); });
        settingsStatus = label("",14,MUTED,false); settings.addView(settingsStatus,rowParams(0,12));
        stop("Disconnected","Open Settings to pair your Windows PC.");
        show(prefs.contains("host") ? 0 : 2);
    }

    private void show(int page) {
        scroll.removeAllViews(); scroll.addView(screens[page]); scroll.scrollTo(0,0);
        for(int i=0;i<3;i++) {
            tabs[i].setTextColor(i==page ? CYAN : MUTED);
            tabs[i].setSelected(i==page);
            tabs[i].setBackground(shape(i==page ? 0xff20394c : 0xff101c2a,12));
        }
    }
    private void refreshAddress() {
        addressPicker.setText(selectedIP+"   ▾");
        addressHint.setText(selectedIP.equals("127.0.0.1") ? "Loopback reaches this phone. A local forward is required to reach the PC." :
            selectedIP.equals("192.168.56.1") ? "Requires a network route to this PC interface." : "Use the same address in the Windows launcher.");
    }
    private GradientDrawable shape(int color,int radius) {
        GradientDrawable drawable=new GradientDrawable(); drawable.setColor(color); drawable.setCornerRadius(dp(radius)); return drawable;
    }
    private int dp(int n) {return Math.round(n * getResources().getDisplayMetrics().density);}
    private LinearLayout column() {
        LinearLayout layout=new LinearLayout(this); layout.setOrientation(LinearLayout.VERTICAL); return layout;
    }
    private TextView label(String s,int size,int color,boolean bold) {
        TextView t=new TextView(this); t.setText(s); t.setTextColor(color); t.setTextSize(size);
        if(bold) t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        return t;
    }
    private Button button(String text) {
        Button b=new Button(this); b.setAllCaps(false); b.setText(text); b.setTextColor(CYAN); b.setBackground(shape(0xff20394c,12));
        b.setStateListAnimator(null); b.setMinHeight(dp(48)); return b;
    }
    private LinearLayout.LayoutParams rowParams(int x,int y) {
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(x),dp(y),dp(x),0); return lp;
    }
    private void styleCard(LinearLayout box) {
        GradientDrawable shape=new GradientDrawable(); shape.setColor(PANEL); shape.setCornerRadius(dp(18)); shape.setStroke(dp(1),0xff26394d);
        box.setBackground(shape); box.setPadding(dp(16),dp(16),dp(16),dp(16));
    }
    private LinearLayout card(LinearLayout parent) {
        LinearLayout box=column(); styleCard(box); parent.addView(box,rowParams(0,10)); return box;
    }
    private EditText field(LinearLayout parent,String title,String value,int type) {
        TextView name=label(title,14,MUTED,false); parent.addView(name,rowParams(0,12));
        EditText input=new EditText(this); input.setId(View.generateViewId()); name.setLabelFor(input.getId());
        input.setInputType(type); input.setSingleLine(true); input.setText(value);
        input.setBackground(shape(0xff0c1929,10)); input.setPadding(dp(12),dp(9),dp(12),dp(9));
        input.setMinHeight(dp(48)); input.setTextSize(16); parent.addView(input,rowParams(0,6)); return input;
    }
    private void message(String title,String text) {
        status.setText(title); detail.setText(text); settingsStatus.setText(title+" · "+text);
    }
    private void controls() {
        for(EditText e: new EditText[]{port,token,interval}) e.setEnabled(!active);
        addressPicker.setEnabled(!active);
        connect.setBackground(shape(active ? 0xff26394d : CYAN,12)); connect.setTextColor(active ? LIGHT : BG);
        connect.setText(active ? "Disconnect" : "Connect");
    }
    private void clear() {
        history.clear(); chart.invalidate(); for(TextView v:values) v.setText("—");
        pc.setText("Awaiting connection");
    }
    private void stop(String title,String reason) {
        generation++; main.removeCallbacksAndMessages(null); active=false; clear(); controls(); message(title,reason);
    }
    private void pair() {
        String ip=selectedIP;
        int p, seconds;
        try {
            p=Integer.parseInt(port.getText().toString());
            seconds=Integer.parseInt(interval.getText().toString());
            if(p<1 || p>65535 || seconds<2 || seconds>30) throw new NumberFormatException();
        } catch(NumberFormatException e) {
            message("Check settings","Use a port from 1–65535 and a refresh interval from 2–30 seconds."); return;
        }
        String address=ip+":"+p, entered=token.getText().toString().trim();
        try {
            String credential=entered.isEmpty() ? Vault.read(prefs,address) : entered;
            if(credential.isEmpty()) {message("Token required","Paste the pairing token from the PC.");return;}
            for(int i=0;i<credential.length();i++) {
                if(credential.charAt(i)<33 || credential.charAt(i)>126) {
                    message("Check token","Paste the single token from the PC.");return;
                }
            }
            token.setText(""); active=true; controls(); message("Connecting",address);
            poll(++generation,address,credential,seconds,!entered.isEmpty());
        } catch(Exception e) {message("Token unavailable","Unlock the phone or enter the token again.");}
    }
    private void poll(int id,String address,String credential,int seconds,boolean save) {
        worker.execute(() -> {
            HttpURLConnection c=null;
            try {
                c=(HttpURLConnection)new URL("http://"+address+"/api/v1/stats").openConnection(Proxy.NO_PROXY);
                c.setConnectTimeout(4500); c.setReadTimeout(4500); c.setInstanceFollowRedirects(false);
                c.setUseCaches(false); c.setRequestProperty("Authorization","Bearer "+credential);
                int code=c.getResponseCode();
                if(code!=200) throw new IOException("HTTP "+code);
                StringBuilder body=new StringBuilder();
                try(Reader r=new InputStreamReader(c.getInputStream(),StandardCharsets.UTF_8)) {
                    char[] chunk=new char[2048]; int n;
                    while((n=r.read(chunk))!=-1) {
                        if(body.length()+n>32768) throw new IOException("Oversized response");
                        body.append(chunk,0,n);
                    }
                }
                JSONObject s=new JSONObject(body.toString());
                main.post(() -> {
                    if(id!=generation)return;
                    try {
                        render(s,address);
                        if(save) Vault.save(prefs,address,credential);
                        prefs.edit().putString("host",selectedIP).putString("port",port.getText().toString())
                            .putString("interval",Integer.toString(seconds)).apply();
                        main.postDelayed(() -> poll(id,address,credential,seconds,false),seconds*1000L);
                    } catch(Exception e) {stop("Connection stopped","Check the server response and pairing token storage.");}
                });
            } catch(Exception e) {
                String reason=e.getMessage();
                main.post(() -> {
                    if(id!=generation)return;
                    if("HTTP 401".equals(reason)) { stop("Pairing failed","Paste the current token from the PC."); return; }
                    clear();
                    message("Unavailable","HTTP 503".equals(reason) ? "Waiting for a fresh sample. Retrying…" :
                        "Check Wi-Fi, the Windows server address, port and firewall. Retrying…");
                    main.postDelayed(() -> poll(id,address,credential,seconds,save),seconds*1000L);
                });
            } finally { if(c!=null)c.disconnect(); }
        });
    }
    private void render(JSONObject s,String address) throws Exception {
        double t=s.getDouble("sampled_at"), cpu=s.getDouble("cpu_percent"), mem=s.getDouble("ram_percent");
        long up=s.getLong("uptime_seconds");
        String name=s.getString("hostname");
        message("Online",name+" · "+address); pc.setText(name+" · "+s.getString("os"));
        values[0].setText(percent(cpu)); values[1].setText(percent(mem));
        values[2].setText(percent(s.getDouble("disk_percent")));
        values[3].setText(String.format(Locale.US,"%dd %dh %dm",up/86400,up/3600%24,up/60%60));
        values[4].setText(rate(s,"upload_bps")); values[5].setText(rate(s,"download_bps"));
        if(!history.isEmpty() && history.get(history.size()-1)[0]>t) history.clear();
        if(history.isEmpty() || history.get(history.size()-1)[0]!=t) history.add(new double[]{t,cpu,mem});
        while(!history.isEmpty() && t-history.get(0)[0]>60) history.remove(0);
        chart.invalidate();
    }
    private String percent(double value) {return String.format(Locale.US,"%.1f%%",value);}
    private String rate(JSONObject s,String key) throws Exception {
        return s.isNull(key) ? "—" : String.format(Locale.US,"%.1f KiB/s",s.getDouble(key)/1024);
    }
    @Override protected void onStop() {
        if(active) stop("Disconnected","Monitoring paused. Tap Connect in Settings to resume.");
        super.onStop();
    }
    @Override protected void onDestroy() {generation++; main.removeCallbacksAndMessages(null); worker.shutdownNow(); super.onDestroy();}
}
