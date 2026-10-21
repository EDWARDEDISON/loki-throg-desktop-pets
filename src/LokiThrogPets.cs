using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace LokiThrogPets {
static class Program {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [STAThread] static void Main(string[] args) {
        SetProcessDPIAware(); Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        try {
            if (args.Length>0 && args[0]=="--self-test") { SelfTest.Run(args.Length>1?args[1]:"qa"); return; }
            bool created; using(var mutex=new Mutex(true,"Local\\LokiThrogPetsPreviewV10",out created)) {
                if(!created) { MessageBox.Show("桌宠已经在运行，请在任务栏托盘中找到绿色小图标。","洛基与雷神"); return; }
                using(var engine=new Engine(false)) {
                    if(args.Length>0 && args[0]=="--smoke-test") {
                        engine.Audio.Enabled=true;engine.Audio.Volume=25;engine.Audio.Play("croak",engine.Time);
                        var timer=new System.Windows.Forms.Timer { Interval=3500 };
                        timer.Tick+=(s,e)=>{timer.Stop();File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"startup-check.txt"),"Native layered windows started; ticks="+engine.Ticks+"; audio play calls="+engine.Audio.Emitted+"; audio error="+engine.Audio.LastError);engine.Quit();};timer.Start();
                    }
                    Application.Run(engine);
                }
            }
        } catch(Exception ex) { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"error.log"),ex.ToString());if(args.Length==0)MessageBox.Show(ex.Message,"桌宠启动失败");Environment.ExitCode=1; }
    }
}

// Small original PCM effects; playback never blocks the WinForms animation timer.
sealed class PetAudio : IDisposable {
    readonly Dictionary<string,byte[]> waves=new Dictionary<string,byte[]>();
    readonly Dictionary<string,System.Media.SoundPlayer> players=new Dictionary<string,System.Media.SoundPlayer>();
    readonly List<MemoryStream> streams=new List<MemoryStream>();
    readonly bool silentTest;bool enabled=true;int volume=25;double lastPlayed=-100;
    public int Accepted,Emitted;public string LastSound="",LastError="";
    public int ResourceCount {get{return waves.Count;}}
    public bool Enabled {get{return enabled;}set{enabled=value;if(!value)Stop();}}
    public int Volume {get{return volume;}set{int v=Math.Max(0,Math.Min(100,value));if(v!=volume){volume=v;ClearPlayers();}}}
    public PetAudio(bool testing){
        silentTest=testing;
        foreach(string name in Assembly.GetExecutingAssembly().GetManifestResourceNames())if(name.StartsWith("sound.")){
            using(Stream s=Assembly.GetExecutingAssembly().GetManifestResourceStream(name))using(var m=new MemoryStream()){s.CopyTo(m);byte[] b=m.ToArray();
                if(b.Length<44||System.Text.Encoding.ASCII.GetString(b,0,4)!="RIFF"||BitConverter.ToInt16(b,34)!=16||BitConverter.ToInt32(b,24)!=22050)throw new InvalidDataException("Invalid sound "+name);
                waves.Add(name.Substring(6),b);
            }
        }
        if(waves.Count!=14)throw new InvalidDataException("Missing sound resources");
        if(!testing)LoadSettings();
    }
    public void Play(string key,double now){
        if(!waves.ContainsKey(key))throw new ArgumentException("Unknown effect: "+key);
        if(!enabled||volume==0||now-lastPlayed<.12)return;
        lastPlayed=now;Accepted++;LastSound=key;if(silentTest)return;
        try{
            System.Media.SoundPlayer player;
            if(!players.TryGetValue(key,out player)){
                byte[] b=(byte[])waves[key].Clone();
                for(int i=44;i+1<b.Length;i+=2){short sample=(short)(BitConverter.ToInt16(b,i)*volume/100);b[i]=(byte)(sample&255);b[i+1]=(byte)((sample>>8)&255);}
                var stream=new MemoryStream(b,false);streams.Add(stream);player=new System.Media.SoundPlayer(stream);player.Load();players.Add(key,player);
            }
            player.Play();Emitted++;
        }catch(Exception ex){LastError=ex.Message;enabled=false;Stop();}
    }
    public void Stop(){foreach(var p in players.Values)try{p.Stop();}catch{}}
    void ClearPlayers(){Stop();foreach(var p in players.Values)p.Dispose();players.Clear();foreach(var s in streams)s.Dispose();streams.Clear();}
    string SettingsPath {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"LokiThrogPets","sound-settings.ini");}}
    void LoadSettings(){try{if(File.Exists(SettingsPath)){string[] rows=File.ReadAllLines(SettingsPath);bool b;int n;if(rows.Length>0&&bool.TryParse(rows[0],out b))enabled=b;if(rows.Length>1&&int.TryParse(rows[1],out n))volume=Math.Max(0,Math.Min(100,n));}}catch{}}
    public void SaveSettings(){if(silentTest)return;try{Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath));File.WriteAllLines(SettingsPath,new[]{enabled.ToString(),volume.ToString()});}catch{}}
    public void Dispose(){ClearPlayers();}
}

sealed class SoundCue {
    public readonly double At;public readonly string Sound;
    public SoundCue(double at,string sound){At=at;Sound=sound;}
}

static class SoundCues {
    public static readonly Dictionary<string,SoundCue[]> All=new Dictionary<string,SoundCue[]> {
        {"hammer",new[]{new SoundCue(2.38,"thud"),new SoundCue(3.2,"giggle"),new SoundCue(6.38,"whoosh")}},
        {"ride",new[]{new SoundCue(2.625,"drop"),new SoundCue(5.417,"croak")}},
        {"cozy",new[]{new SoundCue(4,"soft")}},
        {"mimic",new[]{new SoundCue(2,"magic"),new SoundCue(5,"giggle")}},
        {"zap",new[]{new SoundCue(3.833333,"zap"),new SoundCue(5.1,"giggle")}},
        {"jar",new[]{new SoundCue(1.5,"magic"),new SoundCue(5,"croak"),new SoundCue(8,"chime")}},
        {"snake",new[]{new SoundCue(0.65,"magic"),new SoundCue(5.67,"whoosh"),new SoundCue(7.42,"munch"),new SoundCue(14.12,"drop"),new SoundCue(15.5,"giggle")}},
        {"flight",new[]{new SoundCue(2.58,"whoosh"),new SoundCue(3.67,"munch"),new SoundCue(11.62,"chime"),new SoundCue(12.83,"drop")}},
        {"duobath",new[]{new SoundCue(2.5,"splash"),new SoundCue(6,"splash")}},
        {"swing",new[]{new SoundCue(3.42,"drop"),new SoundCue(8.8,"whoosh"),new SoundCue(9.5,"drop")}},
        {"reconcile",new[]{new SoundCue(5.5,"chime"),new SoundCue(7.6,"giggle")}},
        {"snackshare",new[]{new SoundCue(1.5,"magic"),new SoundCue(5.5,"chime"),new SoundCue(7,"munch")}},
        {"heart",new[]{new SoundCue(2,"heart")}},
        {"bath",new[]{new SoundCue(2,"splash"),new SoundCue(5,"splash")}},
        {"venom",new[]{new SoundCue(2,"magic"),new SoundCue(4,"chirp")}},
        {"doctor",new[]{new SoundCue(2.83,"magic"),new SoundCue(4.25,"chime"),new SoundCue(8.08,"whoosh"),new SoundCue(10.58,"soft")}},
        {"recall",new[]{new SoundCue(1.5,"whoosh"),new SoundCue(4.12,"chime")}},
        {"lightning",new[]{new SoundCue(2.6,"zap")}},
        {"thorheart",new[]{new SoundCue(0.8,"drop"),new SoundCue(2.5,"heart")}},
        {"thorfly",new[]{new SoundCue(2,"whoosh"),new SoundCue(6.83,"drop")}},
        {"gear",new[]{new SoundCue(2.3,"chime")}},
        {"cloud",new[]{new SoundCue(1.5,"croak"),new SoundCue(3.2,"zap")}},
        {"landing",new[]{new SoundCue(2.62,"thud"),new SoundCue(4.1,"croak")}},
        {"thorsleep",new[]{new SoundCue(3,"soft")}},
        {"sparkchase",new[]{new SoundCue(1.8,"zap"),new SoundCue(4.6,"chirp")}},
        {"mirror",new[]{new SoundCue(2.5,"chime")}},
        {"beat",new[]{new SoundCue(1.6,"drop"),new SoundCue(2,"drop"),new SoundCue(2.4,"drop"),new SoundCue(2.8,"drop")}},
        {"greet",new[]{new SoundCue(1.6,"croak")}},
        {"sun",new[]{new SoundCue(3,"soft")}},
        {"run",new[]{new SoundCue(1.3,"whoosh")}},
        {"prank",new[]{new SoundCue(2,"giggle")}},
        {"tailchase",new[]{new SoundCue(2.5,"chirp")}},
        {"horns",new[]{new SoundCue(3,"chime")}},
        {"snack",new[]{new SoundCue(2,"magic"),new SoundCue(4,"munch")}},
        {"laugh",new[]{new SoundCue(1.8,"giggle"),new SoundCue(3.5,"giggle")}},
        {"drag",new[]{new SoundCue(1,"pickup")}},
    };
}

sealed class SpriteLibrary : IDisposable {
    readonly Dictionary<string,Bitmap> images=new Dictionary<string,Bitmap>();
    readonly Dictionary<string,string> resources=new Dictionary<string,string>();
    public SpriteLibrary(){foreach(string name in Assembly.GetExecutingAssembly().GetManifestResourceNames())if(name.StartsWith("sprite."))resources.Add(name.Substring(7),name);if(resources.Count!=454)throw new InvalidDataException("Missing embedded resources: "+resources.Count);}
    public Bitmap this[string key] {get{
        Bitmap result;if(images.TryGetValue(key,out result))return result;
        // Keep only the active interaction atlas decoded. Ordinary pose images are tiny.
        if(key.EndsWith("-atlas"))foreach(string old in new List<string>(images.Keys))if(old.EndsWith("-atlas")){images[old].Dispose();images.Remove(old);}
        using(Stream stream=Assembly.GetExecutingAssembly().GetManifestResourceStream(resources[key]))using(var image=new Bitmap(stream))result=new Bitmap(image);
        images.Add(key,result);return result;
    }}
    public void Dispose(){foreach(var image in images.Values)image.Dispose();images.Clear();}
    public static Bitmap Canvas(int w,int h){return new Bitmap(w,h,PixelFormat.Format32bppArgb);}
    public static void Setup(Graphics g){g.InterpolationMode=InterpolationMode.NearestNeighbor;g.PixelOffsetMode=PixelOffsetMode.Half;g.SmoothingMode=SmoothingMode.None;g.CompositingMode=CompositingMode.SourceOver;}
    public static void Draw(Graphics g,Bitmap image,int x,int y){g.DrawImageUnscaled(image,x,y);}
}

// Each pet has a tight per-pixel-alpha native window. Fully transparent pixels never cover the desktop.
sealed class PetWindow : Form {
    public Action<Point> DragMove; public Action DragStart; public Action<bool> Press;
    Point mouseStart,windowStart; bool held,moved;
    public PetWindow(){FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;TopMost=true;StartPosition=FormStartPosition.Manual;}
    protected override bool ShowWithoutActivation {get{return true;}}
    protected override CreateParams CreateParams {get{var p=base.CreateParams;p.ExStyle|=0x80000|0x80|0x08000000;return p;}}
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);if(e.Button==MouseButtons.Right){if(Press!=null)Press(true);return;}if(e.Button==MouseButtons.Left){held=true;moved=false;mouseStart=Cursor.Position;windowStart=Location;Capture=true;}}
    protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);if(!held)return;var delta=new Size(Cursor.Position.X-mouseStart.X,Cursor.Position.Y-mouseStart.Y);if(!moved&&Math.Abs(delta.Width)+Math.Abs(delta.Height)>5){moved=true;if(DragStart!=null)DragStart();}if(moved&&DragMove!=null)DragMove(windowStart+delta);}
    protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(!held)return;held=false;Capture=false;if(!moved&&Press!=null)Press(false);}
    public void SetFrame(Bitmap frame,Point point,int scale){
        using(var surface=SpriteLibrary.Canvas(frame.Width*scale,frame.Height*scale)){
            using(var g=Graphics.FromImage(surface)){SpriteLibrary.Setup(g);g.DrawImage(frame,new Rectangle(0,0,surface.Width,surface.Height),0,0,frame.Width,frame.Height,GraphicsUnit.Pixel);}
            Native.Layer(this,surface,point);
        }
    }
}

static class Native {
    [StructLayout(LayoutKind.Sequential)] struct P {public int x,y;public P(int a,int b){x=a;y=b;}}
    [StructLayout(LayoutKind.Sequential)] struct S {public int x,y;public S(int a,int b){x=a;y=b;}}
    [StructLayout(LayoutKind.Sequential,Pack=1)] struct Blend {public byte operation,flags,alpha,format;}
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h,IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll",SetLastError=true)] static extern bool UpdateLayeredWindow(IntPtr h,IntPtr dst,ref P pos,ref S size,IntPtr src,ref P origin,int key,ref Blend blend,int flags);
    public static void Layer(Form form,Bitmap image,Point point){
        var dc=GetDC(IntPtr.Zero);var mem=CreateCompatibleDC(dc);IntPtr bitmap=IntPtr.Zero,old=IntPtr.Zero;
        try{bitmap=image.GetHbitmap(Color.FromArgb(0));old=SelectObject(mem,bitmap);var pos=new P(point.X,point.Y);var size=new S(image.Width,image.Height);var origin=new P(0,0);var blend=new Blend{alpha=255,format=1};
            if(!UpdateLayeredWindow(form.Handle,dc,ref pos,ref size,mem,ref origin,0,ref blend,2))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }finally{if(old!=IntPtr.Zero)SelectObject(mem,old);if(bitmap!=IntPtr.Zero)DeleteObject(bitmap);DeleteDC(mem);ReleaseDC(IntPtr.Zero,dc);}
    }
}

sealed class Pet {
    public bool Frog,Left,Dragging,MenuHeld,HasRoute;public double RoamTarget;public Rectangle RoamArea;public double X,Ground,Age,Until,NextSoloAt,LastEncounterAt;public string State="idle";
    public int Width {get{return Frog?128:200;}}
}

sealed class Engine : ApplicationContext {
    public readonly SpriteLibrary Art=new SpriteLibrary();public readonly PetAudio Audio;
    public readonly Pet Loki=new Pet(),Thor=new Pet{Frog=true};
    public int Scale=2;public bool AutoWalk=true,AutoPair=true,AutoSolo=true,Paused;public long Ticks;
    public string Solo="",Pair="";public bool SoloGathering,Gathering,Seeking;public double SoloAge,PairAge,Time,PairCooldownUntil;
    public const int SoloMinSeconds=180,SoloMaxSeconds=300,EncounterCooldownSeconds=30,EncounterGap=16;
    readonly Random random;readonly bool test;readonly PetWindow lokiWindow,thorWindow,pairWindow,soloWindow;
    readonly System.Windows.Forms.Timer clock;readonly Stopwatch elapsed=new Stopwatch();readonly NotifyIcon tray;
    readonly ContextMenuStrip menu,lokiMenu,thorMenu;double last;bool contactLatched;
    Pet soloActor,seeker,seekPartner;Point soloStage,soloTarget,stage,lokiTarget,thorTarget;
    public static readonly string[] PairKinds=new[]{"hammer","ride","cozy","mimic","zap","jar","snake","flight","duobath","swing","reconcile","snackshare"};
    public static readonly string[] SoloKinds=new[]{"heart","bath","venom","doctor","recall","lightning","thorheart","thorfly","gear","cloud","landing","thorsleep","sparkchase","mirror","beat","greet","sun","run","prank","tailchase","horns","snack","laugh","drag"};
    public static readonly string[] LokiKinds=new[]{"heart","bath","venom","doctor","sun","run","prank","tailchase","horns","snack","laugh","drag"};
    public static readonly string[] ThorKinds=new[]{"recall","lightning","thorheart","thorfly","gear","cloud","landing","thorsleep","sparkchase","mirror","beat","greet"};
    public static bool IsThorSolo(string kind){return Array.IndexOf(ThorKinds,kind)>=0;}
    public static int PairSeconds(string kind){switch(kind){case "hammer":return 9;case "ride":return 12;case "cozy":return 16;case "mimic":return 10;case "zap":return 12;case "jar":return 12;case "snake":return 20;case "flight":return 20;case "duobath":return 14;case "swing":return 13;case "reconcile":return 12;case "snackshare":return 14;default:throw new ArgumentException(kind);}}
    public static int PairFps(string kind){return 24;}
    public static int PairWidth(string kind){return kind=="flight"?512:384;}
    public static int SoloSeconds(string kind){switch(kind){case "heart":return 6;case "bath":return 10;case "venom":return 8;case "doctor":return 16;case "recall":return 6;case "lightning":return 6;case "thorheart":return 8;case "thorfly":return 9;case "gear":return 10;case "cloud":return 10;case "landing":return 7;case "thorsleep":return 12;case "sparkchase":return 8;case "mirror":return 8;case "beat":return 7;case "greet":return 6;case "sun":return 10;case "run":return 8;case "prank":return 7;case "tailchase":return 9;case "horns":return 8;case "snack":return 8;case "laugh":return 6;case "drag":return 7;default:throw new ArgumentException(kind);}}
    public static string ActionTitle(string kind){switch(kind){case "hammer":return "锤子压洛基";case "ride":return "骑鳄鱼巡游";case "cozy":return "一条披风，一起休息";case "heart":return "洛基比心";case "bath":return "洛基泡泡浴";case "venom":return "毒液变装";case "doctor":return "奇异博士变装";case "recall":return "雷神召回锤子";case "lightning":return "雷神小雷电";case "mimic":return "洛基假扮鳄鱼雷神";case "zap":return "偷偷电一下尾巴";case "jar":return "透明魔法罐子";case "snake":return "舌头卷入 · 变蛇恶作剧";case "flight":return "掷锤 · 飞扑咬住 · 随锤飞";case "thorheart":return "雷神比心";case "thorfly":return "甩锤起飞";case "gear":return "擦锤子，整理装备";case "cloud":return "蛙叫小雷雨";case "landing":return "英雄落地，偷偷揉脚";case "thorsleep":return "抱锤裹披风打盹";case "sparkchase":return "追一颗小闪电";case "mirror":return "照镜子，扶正翼盔";case "beat":return "用锤柄敲节拍";case "greet":return "向你挥手打招呼";case "sun":return "晒太阳打盹";case "run":return "洛基小跑";case "prank":return "搓爪，假装无辜";case "tailchase":return "追自己的尾巴";case "horns":return "梳理金角";case "snack":return "变出小零食";case "laugh":return "洛基开怀大笑";case "drag":return "被拎起，四脚蹬蹬";case "duobath":return "洗澡搭档";case "swing":return "尾巴秋千";case "reconcile":return "闹完碰拳和好";case "snackshare":return "分一半零食给哥哥";default:throw new ArgumentException(kind);}}
    public Engine(bool testing){
        test=testing;Audio=new PetAudio(testing);random=testing?new Random(17):new Random();var area=Screen.PrimaryScreen.WorkingArea;
        Loki.X=area.Right-680;Thor.X=area.Right-240;Loki.Ground=Thor.Ground=area.Bottom;
        foreach(Pet p in new[]{Loki,Thor}){p.State="walk";p.Left=random.Next(2)==0;p.Until=18+random.Next(13);ScheduleSolo(p);Clamp(p);EnsureRoute(p);}
        if(!test){
            lokiWindow=MakeWindow(Loki);thorWindow=MakeWindow(Thor);
            pairWindow=new PetWindow();pairWindow.Press=(right)=>{if(right)ShowMenu();else CancelPair();};
            soloWindow=new PetWindow();soloWindow.Press=(right)=>{if(right)ShowPetMenu(soloActor);else CancelSolo();};
            menu=MakeGlobalMenu();lokiMenu=MakePetMenu(Loki);thorMenu=MakePetMenu(Thor);
            tray=new NotifyIcon{Text="洛基与雷神 · 右键角色选择动作",Icon=MakeIcon(),ContextMenuStrip=menu,Visible=true};tray.DoubleClick+=(s,e)=>Reset();
            Render();lokiWindow.Show();thorWindow.Show();elapsed.Start();clock=new System.Windows.Forms.Timer{Interval=16};
            clock.Tick+=(s,e)=>{double now=elapsed.Elapsed.TotalSeconds;Step(Math.Min(.25,now-last));last=now;Render();};clock.Start();
        }
    }
    ContextMenuStrip MakePetMenu(Pet p){
        var m=new ContextMenuStrip();var title=new ToolStripMenuItem(p.Frog?"青蛙雷神":"鳄鱼洛基"){Enabled=false};m.Items.Add(title);
        var singles=new ToolStripMenuItem("我的单人动作");
        foreach(string key in p.Frog?ThorKinds:LokiKinds){string action=key;singles.DropDownItems.Add(ActionTitle(action),null,(s,e)=>RequestSolo(action));}m.Items.Add(singles);
        var find=new ToolStripMenuItem(p.Frog?"去找弟弟互动":"去找哥哥互动");
        find.DropDownItems.Add("随机互动（12 种等概率）",null,(s,e)=>Seek(p,ChoosePair()));find.DropDownItems.Add(new ToolStripSeparator());
        foreach(string key in PairKinds){string action=key;find.DropDownItems.Add(ActionTitle(action),null,(s,e)=>Seek(p,action));}m.Items.Add(find);
        m.Items.Add("睡觉 / 醒来",null,(s,e)=>ToggleSleep(p));m.Items.Add("转身",null,(s,e)=>{SetRoamTarget(p,!p.Left);});
        m.Items.Add("回到屏幕下方",null,(s,e)=>{CancelSolo();CancelPair();p.Ground=Area(p).Bottom;p.HasRoute=false;Clamp(p);});
        m.Items.Add(new ToolStripSeparator());m.Items.Add("全局设置…",null,(s,e)=>ShowMenu());m.Items.Add("退出桌宠",null,(s,e)=>Quit());
        m.Opening+=(s,e)=>{p.MenuHeld=true;};m.Closed+=(s,e)=>{p.MenuHeld=false;p.Until=Math.Max(p.Until,Time+1);};return m;
    }
    ContextMenuStrip MakeGlobalMenu(){
        var m=new ContextMenuStrip();m.Items.Add("洛基动作与互动…",null,(s,e)=>ShowPetMenu(Loki));m.Items.Add("雷神动作与互动…",null,(s,e)=>ShowPetMenu(Thor));
        m.Items.Add("结束当前动作 / 寻找",null,(s,e)=>{CancelSolo();CancelPair();});m.Items.Add("两只回到屏幕下方",null,(s,e)=>Reset());
        var walk=new ToolStripMenuItem("各自自由移动"){Checked=true,CheckOnClick=true};walk.CheckedChanged+=(s,e)=>{AutoWalk=walk.Checked;if(!AutoWalk)foreach(Pet p in new[]{Loki,Thor})if(p.State=="walk"&&Pair==""&&Solo=="")p.State="idle";};m.Items.Add(walk);
        var meet=new ToolStripMenuItem("碰面后随机互动（各 1/12）"){Checked=true,CheckOnClick=true};meet.CheckedChanged+=(s,e)=>{AutoPair=meet.Checked;contactLatched=false;};m.Items.Add(meet);
        var solos=new ToolStripMenuItem("没碰面时每 3～5 分钟单人表演"){Checked=true,CheckOnClick=true};solos.CheckedChanged+=(s,e)=>{AutoSolo=solos.Checked;ScheduleSolo(Loki);ScheduleSolo(Thor);};m.Items.Add(solos);
        var sound=new ToolStripMenuItem("播放像素音效"){Checked=Audio.Enabled,CheckOnClick=true};
        sound.CheckedChanged+=(s,e)=>{Audio.Enabled=sound.Checked;Audio.SaveSettings();};m.Items.Add(sound);
        var volume=new ToolStripMenuItem("音量（默认 25%）");
        foreach(int n in new[]{10,25,50,75,100}){int value=n;var item=new ToolStripMenuItem(n+"%"){Checked=Audio.Volume==n};item.Click+=(s,e)=>{Audio.Volume=value;Audio.Enabled=true;sound.Checked=true;foreach(ToolStripMenuItem other in volume.DropDownItems)other.Checked=other==item;Audio.SaveSettings();Audio.Play("chime",Time);};volume.DropDownItems.Add(item);}m.Items.Add(volume);
        m.Items.Add("试听：雷神蛙叫",null,(s,e)=>Audio.Play("croak",Time));
        var pause=new ToolStripMenuItem("暂停"){CheckOnClick=true};pause.CheckedChanged+=(s,e)=>{Paused=pause.Checked;if(Paused)Audio.Stop();};m.Items.Add(pause);
        var size=new ToolStripMenuItem("大小");for(int i=1;i<=3;i++){int value=i;size.DropDownItems.Add(i+" 倍",null,(s,e)=>ResizePets(value));}m.Items.Add(size);
        m.Items.Add("操作说明",null,(s,e)=>MessageBox.Show("两只各自移动，碰面后从 12 种互动等概率选择。\n没有碰面时，各自每 3～5 分钟随机做单人动作。\n右键某只角色：点播自己的单人动作，或走去找对方互动。\n左键拖动：洛基蹬脚，雷神悬空蹬腿；轻点触发表情和音效。\n互动时轻点可结束。自由移动按屏幕远端巡游，短暂停步后继续原路线。\n可开关音效、调音量；设置会记住。\n右键菜单展开时，该角色暂时停步。\n\n不设置开机启动，不联网。","洛基与雷神"));
        m.Items.Add(new ToolStripSeparator());m.Items.Add("退出桌宠",null,(s,e)=>Quit());return m;
    }
    void ShowMenu(){menu.Show(Cursor.Position);}void ShowPetMenu(Pet p){(p.Frog?thorMenu:lokiMenu).Show(Cursor.Position);}
    Icon MakeIcon(){using(var b=new Bitmap(32,32)){using(var g=Graphics.FromImage(b)){SpriteLibrary.Setup(g);g.DrawImage(Art["throg-reach"],new Rectangle(0,0,32,32));}var h=b.GetHicon();try{return (Icon)Icon.FromHandle(h).Clone();}finally{DestroyIcon(h);}}}
    [DllImport("user32.dll")]static extern bool DestroyIcon(IntPtr h);
    PetWindow MakeWindow(Pet p){var w=new PetWindow();w.DragStart=()=>BeginDrag(p);w.DragMove=(point)=>{p.X=point.X;p.Ground=point.Y+120*Scale;Clamp(p);};w.Press=(right)=>{if(right)ShowPetMenu(p);else{p.State="react";p.Age=0;p.Until=Time+1.4;Audio.Play(p.Frog?"croak":"chirp",Time);}};w.MouseUp+=(s,e)=>EndDrag(p);return w;}
    Rectangle Area(Pet p){return Screen.FromPoint(new Point((int)p.X+p.Width*Scale/2,(int)p.Ground-40)).WorkingArea;}
    public void Clamp(Pet p){var a=Area(p);p.X=Math.Max(a.Left,Math.Min(a.Right-p.Width*Scale,p.X));p.Ground=Math.Max(a.Top+120*Scale,Math.Min(a.Bottom,p.Ground));}
    void Reset(){CancelSolo();CancelPair();var a=Screen.FromPoint(Cursor.Position).WorkingArea;Loki.X=a.Right-680;Thor.X=a.Right-240;foreach(Pet p in new[]{Loki,Thor}){p.Ground=a.Bottom;p.HasRoute=false;p.State="idle";p.Until=Time+3;Clamp(p);}contactLatched=false;}
    void ResizePets(int scale){CancelSolo();CancelPair();Scale=scale;Loki.HasRoute=Thor.HasRoute=false;Clamp(Loki);Clamp(Thor);Render();}
    void ToggleSleep(Pet p){CancelSolo();CancelPair();p.State=p.State=="sleep"?"wake":"settle";p.Until=Time+(p.State=="wake"?1:2);p.Age=0;}
    void ScheduleSolo(Pet p){p.NextSoloAt=Time+SoloMinSeconds+random.Next(SoloMaxSeconds-SoloMinSeconds+1);}
    bool Ready(Pet p){return !p.Dragging&&!p.MenuHeld&&(p.State=="idle"||p.State=="walk");}
    public bool Near(){
        if(!Area(Loki).Equals(Area(Thor))||Math.Abs(Loki.Ground-Thor.Ground)>24*Scale)return false;
        double ll=Loki.X+(Loki.Left?0:32)*Scale,lr=ll+168*Scale,tl=Thor.X+20*Scale,tr=tl+88*Scale;
        double gap=Math.Max(ll,tl)-Math.Min(lr,tr);return gap<=EncounterGap*Scale;
    }
    public string ChoosePair(){return PairKinds[random.Next(PairKinds.Length)];}
    public void Request(string kind){PairSeconds(kind);CancelSolo();CancelPair();Pair=kind;BeginStaging(Loki);}
    public void Seek(Pet requester,string kind){
        PairSeconds(kind);CancelSolo();CancelPair();Pair=kind;Gathering=true;Seeking=true;PairAge=0;seeker=requester;seekPartner=requester==Loki?Thor:Loki;
        seeker.Dragging=seekPartner.Dragging=false;seeker.State="walk";seeker.Age=0;seekPartner.State="idle";seekPartner.Age=0;
        if(Near())BeginStaging(seekPartner);
    }
    Point SeekTarget(){
        var a=Area(seekPartner);double x=seeker.X<seekPartner.X?seekPartner.X-seeker.Width*Scale+20*Scale:seekPartner.X+seekPartner.Width*Scale-20*Scale;
        if(x<a.Left)x=seekPartner.X+seekPartner.Width*Scale-20*Scale;
        if(x+seeker.Width*Scale>a.Right)x=seekPartner.X-seeker.Width*Scale+20*Scale;
        x=Math.Max(a.Left,Math.Min(a.Right-seeker.Width*Scale,x));return new Point((int)x,(int)seekPartner.Ground);
    }
    void BeginStaging(Pet anchor){
        var a=Area(anchor);int width=PairWidth(Pair)*Scale;double center=(Loki.X+Loki.Width*Scale/2+Thor.X+Thor.Width*Scale/2)/2;
        int left=(int)center-width/2;left=Math.Max(a.Left,Math.Min(a.Right-width,left));int ground=(int)anchor.Ground;ground=Math.Max(a.Top+214*Scale,Math.Min(a.Bottom,ground));
        stage=new Point(left,ground-214*Scale);lokiTarget=new Point(left+(214-Loki.Width)*Scale,ground);thorTarget=new Point(left+(296-Thor.Width/2)*Scale,ground);
        Seeking=false;Gathering=true;PairAge=0;Loki.State=Thor.State="walk";Loki.Age=Thor.Age=0;
    }
    public void CancelPair(){
        if(Pair=="")return;Pair="";Gathering=Seeking=false;seeker=seekPartner=null;PairCooldownUntil=Time+EncounterCooldownSeconds;
        foreach(Pet p in new[]{Loki,Thor}){p.State="idle";p.Age=0;p.Until=Time+3;p.LastEncounterAt=Time;ScheduleSolo(p);}Loki.Left=false;Thor.Left=true;contactLatched=Near();
        if(!test){pairWindow.Hide();lokiWindow.Show();thorWindow.Show();}
    }
    public void RequestSolo(string kind){
        SoloSeconds(kind);CancelSolo();CancelPair();soloActor=IsThorSolo(kind)?Thor:Loki;var a=Area(soloActor);int anchor=soloActor.Frog?192-soloActor.Width/2:256-soloActor.Width;int x=(int)soloActor.X-anchor*Scale;
        x=Math.Max(a.Left,Math.Min(a.Right-384*Scale,x));int ground=Math.Max(a.Top+214*Scale,Math.Min(a.Bottom,(int)soloActor.Ground));
        soloStage=new Point(x,ground-214*Scale);soloTarget=new Point(x+anchor*Scale,ground);Solo=kind;SoloGathering=true;SoloAge=0;soloActor.State="walk";soloActor.Age=0;soloActor.Dragging=false;
    }
    public void CancelSolo(){if(Solo=="")return;soloActor.State="idle";soloActor.Age=0;soloActor.Until=Time+3;soloActor.Left=false;ScheduleSolo(soloActor);Solo="";SoloGathering=false;if(!test){soloWindow.Hide();(soloActor.Frog?thorWindow:lokiWindow).Show();}}
    bool Approach(Pet p,Point target,double dt){double dx=target.X-p.X,dy=target.Y-p.Ground,distance=Math.Sqrt(dx*dx+dy*dy),step=100*Scale*dt;p.Left=dx<0;p.Age+=dt;if(distance<=step){p.X=target.X;p.Ground=target.Y;return true;}p.X+=dx/distance*step;p.Ground+=dy/distance*step;return false;}
    public void EvaluateAutonomy(){
        if(Pair!=""||Solo!="")return;
        bool near=Near();if(!near)contactLatched=false;
        if(AutoPair&&near&&!contactLatched&&Time>=PairCooldownUntil&&Ready(Loki)&&Ready(Thor)){contactLatched=true;Request(ChoosePair());return;}
        if(!AutoSolo)return;
        bool l=Ready(Loki)&&Time>=Loki.NextSoloAt,t=Ready(Thor)&&Time>=Thor.NextSoloAt;Pet actor=null;
        if(l&&t)actor=Loki.NextSoloAt<Thor.NextSoloAt?Loki:Thor;else if(l)actor=Loki;else if(t)actor=Thor;
        if(actor!=null){string[] choices=actor.Frog?ThorKinds:LokiKinds;RequestSolo(choices[random.Next(choices.Length)]);}
    }
    public void Step(double dt){
        Ticks++;if(Paused)return;Time+=dt;
        if(Solo!=""){
            UpdatePet(soloActor==Loki?Thor:Loki,dt);
            if(soloActor.MenuHeld)return;
            if(SoloGathering){if(Approach(soloActor,soloTarget,dt)){SoloGathering=false;SoloAge=0;soloActor.Left=false;if(!test){(soloActor.Frog?thorWindow:lokiWindow).Hide();soloWindow.Show();}}return;}
            double prior=SoloAge;SoloAge+=dt;PlayCues(Solo,prior,SoloAge);if(SoloAge>=SoloSeconds(Solo))CancelSolo();return;
        }
        if(Pair!=""){
            if(Loki.MenuHeld||Thor.MenuHeld)return;
            if(Seeking){seekPartner.Age+=dt;seekPartner.Left=seeker.X<seekPartner.X;if(Approach(seeker,SeekTarget(),dt))BeginStaging(seekPartner);return;}
            if(Gathering){bool a=Approach(Loki,lokiTarget,dt),b=Approach(Thor,thorTarget,dt);if(a&&b){Gathering=false;PairAge=0;Loki.Left=false;Thor.Left=true;if(!test){lokiWindow.Hide();thorWindow.Hide();pairWindow.Show();}}return;}
            double prior=PairAge;PairAge+=dt;PlayCues(Pair,prior,PairAge);if(PairAge>=PairSeconds(Pair)){Loki.X=stage.X+(214-Loki.Width)*Scale;Thor.X=stage.X+(296-Thor.Width/2)*Scale;Loki.Ground=Thor.Ground=stage.Y+214*Scale;CancelPair();Clamp(Loki);Clamp(Thor);}return;
        }
        UpdatePet(Loki,dt);UpdatePet(Thor,dt);EvaluateAutonomy();
    }
    // A destination survives short rests and interactions. Only arrival, dragging,
    // a screen/size change, or an explicit turn selects a different destination.
    public void SetRoamTarget(Pet p,bool left){var a=Area(p);p.RoamTarget=left?a.Left:Math.Max(a.Left,a.Right-p.Width*Scale);p.RoamArea=a;p.HasRoute=true;p.Left=left;}
    void EnsureRoute(Pet p){
        var a=Area(p);double right=Math.Max(a.Left,a.Right-p.Width*Scale);
        if(!p.HasRoute||!a.Equals(p.RoamArea)||p.RoamTarget<a.Left||p.RoamTarget>right)
            SetRoamTarget(p,p.X>(a.Left+right)/2);
    }
    public void BeginDrag(Pet p){CancelSolo();CancelPair();p.Dragging=true;p.HasRoute=false;p.Age=0;p.State="idle";Audio.Play(p.Frog?"croak":"pickup",Time);}
    public void EndDrag(Pet p){if(!p.Dragging)return;p.Dragging=false;p.HasRoute=false;p.State="drop";p.Age=0;p.Until=Time+.45;Audio.Play("drop",Time);}
    void UpdatePet(Pet p,double dt){
        if(p.MenuHeld)return;if(p.Dragging){p.Age+=dt;return;}p.Age+=dt;
        if(p.State=="sleep")return;
        if(p.State=="settle"){if(p.Age>=2){p.State="sleep";p.Age=0;p.Until=double.MaxValue;}return;}
        if(p.State=="wake"&&p.Age>=1){p.State="idle";p.Age=0;p.Until=Time+2;return;}
        if(p.State=="walk"){
            if(!AutoWalk){p.State="idle";p.Until=Time+2;return;}
            EnsureRoute(p);double dx=p.RoamTarget-p.X;double step=(p.Frog?30:24)*Scale*dt;
            p.Left=dx<0;
            if(Math.Abs(dx)<=step){p.X=p.RoamTarget;p.HasRoute=false;p.State="idle";p.Age=0;p.Until=Time+1.5+random.NextDouble()*2;return;}
            p.X+=Math.Sign(dx)*step;
            // A brief breather preserves the distant destination and heading.
            if(Time>=p.Until){p.State="idle";p.Age=0;p.Until=Time+.7+random.NextDouble()*1.1;}
            return;
        }
        if(Time>=p.Until){
            p.Age=0;if(AutoWalk){EnsureRoute(p);p.State="walk";p.Left=p.RoamTarget<p.X;p.Until=Time+18+random.Next(13);}
            else{p.State="idle";p.Until=Time+2;}
        }
    }
    public void PlayCues(string kind,double before,double after){
        SoundCue[] cues;if(!SoundCues.All.TryGetValue(kind,out cues))return;
        foreach(var c in cues)if(c.At>before&&c.At<=after)Audio.Play(c.Sound,Time);
    }

    public Bitmap SoloFrame(){int count=SoloSeconds(Solo)*24;int index=Math.Min(count-1,(int)(SoloAge*24));var frame=SpriteLibrary.Canvas(384,256);using(var g=Graphics.FromImage(frame)){SpriteLibrary.Setup(g);g.DrawImage(Art[Solo+"-atlas"],new Rectangle(0,0,384,256),new Rectangle(index%12*384,index/12*256,384,256),GraphicsUnit.Pixel);}return frame;}
    public Bitmap PetFrame(Pet p){
        var frame=SpriteLibrary.Canvas(p.Width,120);using(var g=Graphics.FromImage(frame)){SpriteLibrary.Setup(g);Bitmap sprite;int offset=0;
            if(p.Dragging){
                int[] cycle=new[]{2,3,2,4,2,5,6,2};int n=p.Age<.22?1:cycle[(int)((p.Age-.22)*7)%cycle.Length];
                sprite=Art[p.Frog?"u10-thordrag-"+n:((int)(p.Age*6)%2==0?"u8-ld-11":"u8-lx-6")];
            }
            else if(p.State=="drop")sprite=Art[p.Frog?(p.Age<.2?"u10-thordrag-7":"thor-crouch-low"):(p.Age<.2?"loki-lower":"loki-idle")];
            else if(p.State=="walk"){
                int n=(int)(p.Age*12)%8;
                if(p.Frog){double phase=p.Age*1.5%1;sprite=Art[phase<.18?"thor-crouch-low":phase>.84?"u7-tb-4":"thor-air-low"];offset=phase<.18||phase>.84?0:(int)(Math.Sin((phase-.18)/.66*Math.PI)*16)/2*2;}
                else sprite=Art["loki-walk-"+n];
            }
            else if(p.State=="settle"){
                if(p.Frog)sprite=Art[p.Age<.5?"thor-crouch-low":"throg-sleep"];
                else sprite=Art[p.Age<.6?"loki-lower":p.Age<1.2?"loki-lie":"loki-sleep-natural"];
            }
            else if(p.State=="wake")sprite=Art[p.Frog?"thor-crouch-low":p.Age<.5?"loki-rise":"loki-lower"];
            else if(p.State=="sleep")sprite=Art[p.Frog?"throg-sleep":"loki-sleep-natural"];
            else if(p.State=="react")sprite=Art[p.Frog?"throg-laugh":"loki-flat"];
            else sprite=Art[p.Frog?"thor-idle-low":"loki-idle"];
            int x=p.Frog?(p.Width-sprite.Width)/2:p.Width-sprite.Width;SpriteLibrary.Draw(g,sprite,x,p.Frog&&p.Dragging?10:120-sprite.Height-offset);
            // Held hammer is already drawn in these generated poses; never add a second one.
        }if(p.Left)frame.RotateFlip(RotateFlipType.RotateNoneFlipX);return frame;
    }
    public Bitmap PairFrame(){
        int fps=PairFps(Pair),width=PairWidth(Pair),count=PairSeconds(Pair)*fps;
        int index=Math.Min(count-1,(int)(PairAge*fps));var frame=SpriteLibrary.Canvas(width,256);
        using(var g=Graphics.FromImage(frame)){SpriteLibrary.Setup(g);g.DrawImage(Art[Pair+"-atlas"],new Rectangle(0,0,width,256),new Rectangle((index%12)*width,(index/12)*256,width,256),GraphicsUnit.Pixel);}return frame;
    }
    void RenderPet(Pet p,PetWindow window){using(var frame=PetFrame(p))window.SetFrame(frame,new Point((int)Math.Round(p.X/2)*2,(int)Math.Round(p.Ground)-120*Scale),Scale);}
    void Render(){if(test)return;
        if(Pair!=""&&!Gathering){using(var frame=PairFrame())pairWindow.SetFrame(frame,stage,Scale);return;}
        if(Solo!=""&&!SoloGathering){using(var frame=SoloFrame())soloWindow.SetFrame(frame,soloStage,Scale);}
        if(Solo==""||SoloGathering||soloActor!=Loki)RenderPet(Loki,lokiWindow);
        if(Solo==""||SoloGathering||soloActor!=Thor)RenderPet(Thor,thorWindow);
    }

    public void Quit(){if(clock!=null)clock.Stop();if(tray!=null)tray.Visible=false;ExitThread();}
    protected override void Dispose(bool disposing){if(disposing){if(clock!=null)clock.Dispose();if(tray!=null){var icon=tray.Icon;tray.Dispose();if(icon!=null)icon.Dispose();}if(menu!=null)menu.Dispose();if(lokiMenu!=null)lokiMenu.Dispose();if(thorMenu!=null)thorMenu.Dispose();if(lokiWindow!=null)lokiWindow.Dispose();if(thorWindow!=null)thorWindow.Dispose();if(pairWindow!=null)pairWindow.Dispose();if(soloWindow!=null)soloWindow.Dispose();Audio.Dispose();Art.Dispose();}base.Dispose(disposing);}
}

static class SelfTest {
    static int checks;
    static void Assert(bool condition,string reason){checks++;if(!condition)throw new Exception("Self-test failed: "+reason);}
    static int Visible(Bitmap bitmap){int n=0;for(int y=0;y<bitmap.Height;y+=2)for(int x=0;x<bitmap.Width;x+=2)if(bitmap.GetPixel(x,y).A>0)n++;return n;}
    static void PolicyChecks(Engine e){
        e.CancelSolo();e.CancelPair();e.Scale=1;e.AutoWalk=false;e.AutoPair=true;e.AutoSolo=false;e.Paused=false;
        var a=Screen.PrimaryScreen.WorkingArea;
        e.Loki.X=a.Left+10;e.Thor.X=a.Right-e.Thor.Width-10;e.Loki.Ground=e.Thor.Ground=a.Bottom;
        foreach(Pet p in new[]{e.Loki,e.Thor}){p.State="idle";p.Until=double.MaxValue;p.MenuHeld=p.Dragging=false;}
        e.Step(65);Assert(e.Pair=="","a timer forced a pair despite no encounter");
        e.Loki.X=a.Left+100;e.Loki.Left=false;e.Thor.X=e.Loki.X+180;e.Thor.Left=true;
        Assert(e.Near(),"contact geometry missed touching pet outlines");e.PairCooldownUntil=e.Time+30;e.EvaluateAutonomy();Assert(e.Pair=="","encounter cooldown ignored");
        e.Time+=31;e.EvaluateAutonomy();Assert(e.Pair!="","new contact did not start pair");e.CancelPair();e.AutoPair=false;
        e.Loki.X=a.Left+10;e.Thor.X=a.Right-e.Thor.Width-10;e.AutoSolo=true;e.Loki.NextSoloAt=e.Time+180;e.Thor.NextSoloAt=e.Time+300;
        e.Step(179);Assert(e.Solo=="","solo fired before its per-pet wait");e.Step(1.1);Assert(Array.IndexOf(Engine.LokiKinds,e.Solo)>=0,"due Loki timer selected wrong actor or action");e.CancelSolo();
        Assert(e.Loki.NextSoloAt-e.Time>=180&&e.Loki.NextSoloAt-e.Time<=300,"solo next wait outside 3-5 minutes");
        e.Loki.NextSoloAt=e.Time;e.Thor.NextSoloAt=e.Time+300;e.Loki.MenuHeld=true;e.EvaluateAutonomy();Assert(e.Solo=="","menu-held pet started solo");
        e.Loki.MenuHeld=false;e.Loki.State="sleep";e.EvaluateAutonomy();Assert(e.Solo=="","sleeping pet was woken by automatic solo");e.Loki.State="idle";e.AutoSolo=false;
        var counts=new Dictionary<string,int>();foreach(string k in Engine.PairKinds)counts[k]=0;
        for(int i=0;i<120000;i++)counts[e.ChoosePair()]++;
        foreach(string k in Engine.PairKinds)Assert(counts[k]>9000&&counts[k]<11000,"pair distribution badly biased: "+k);
        e.Thor.X=a.Right-e.Thor.Width-10;e.Seek(e.Thor,"snackshare");Assert(e.Seeking,"manual request skipped the find-partner phase");
        int steps=0;while(e.Seeking&&steps++<600)e.Step(1.0/12);Assert(!e.Seeking&&e.Gathering,"manual seeker did not reach partner before staging");
        e.CancelPair();Assert(e.Thor.NextSoloAt-e.Time>=180&&e.Loki.NextSoloAt-e.Time>=180,"encounter did not reset both solo clocks");
    }

    static void NewChecks(Engine e,string path){
        e.CancelPair();e.CancelSolo();e.AutoPair=e.AutoSolo=false;e.AutoWalk=true;e.Paused=false;
        var a=Screen.PrimaryScreen.WorkingArea;
        foreach(int scale in new[]{1,2}){
            e.Scale=scale;
            foreach(Pet p in new[]{e.Loki,e.Thor}){p.X=a.Left+(a.Width-p.Width*scale)*.5;p.Ground=a.Bottom;p.HasRoute=false;p.State="walk";p.Until=e.Time+20;p.MenuHeld=p.Dragging=false;}
            double lmin=e.Loki.X,lmax=lmin,tmin=e.Thor.X,tmax=tmin;
            // More than two real screen traversals, including rests, with normal policy.
            double duration=3.4*a.Width/(24*scale)+45;
            for(int i=0;i<duration*12;i++){
                e.Step(1.0/12);lmin=Math.Min(lmin,e.Loki.X);lmax=Math.Max(lmax,e.Loki.X);tmin=Math.Min(tmin,e.Thor.X);tmax=Math.Max(tmax,e.Thor.X);
                foreach(Pet p in new[]{e.Loki,e.Thor})Assert(p.X>=a.Left-.01&&p.X+p.Width*scale<=a.Right+.01,"roaming escaped work area");
            }
            Assert(lmin<=a.Left+2&&lmax>=a.Right-e.Loki.Width*scale-2,"Loki did not traverse both screen edges");
            Assert(tmin<=a.Left+2&&tmax>=a.Right-e.Thor.Width*scale-2,"Thor did not traverse both screen edges");
            e.Loki.X=a.Left+30;e.Loki.State="walk";e.SetRoamTarget(e.Loki,false);e.Loki.Until=e.Time+.1;e.Step(.11);
            double target=e.Loki.RoamTarget;Assert(e.Loki.State=="idle","long walk did not take its brief rest");e.Step(2);
            Assert(e.Loki.State=="walk"&&e.Loki.RoamTarget==target&&!e.Loki.Left,"rest changed unfinished route");
            // The explicit turn replaces the destination instead of being undone next tick.
            e.SetRoamTarget(e.Loki,true);e.Step(.1);Assert(e.Loki.Left,"manual turn was immediately undone");
        }
        e.Scale=1;e.AutoWalk=false;Pet frog=e.Thor;frog.X=a.Left+80;frog.Ground=a.Bottom;frog.Left=false;
        int before=e.Audio.Accepted;e.BeginDrag(frog);Assert(frog.Dragging,"pickup did not enter dragging");
        var hashes=new HashSet<long>();
        for(int i=0;i<20;i++){
            frog.Age=i*.13;
            using(var b=e.PetFrame(frog)){
                Assert(Visible(b)>200,"empty lifted Frog Thor frame");long h=17;
                unchecked{for(int y=0;y<b.Height;y+=2)for(int x=0;x<b.Width;x+=2)h=h*31+b.GetPixel(x,y).ToArgb();}hashes.Add(h);
                for(int y=0;y<b.Height;y++)Assert(b.GetPixel(0,y).A==0&&b.GetPixel(b.Width-1,y).A==0,"pickup sprite clipped horizontally");
                for(int x=0;x<b.Width;x++)Assert(b.GetPixel(x,0).A==0,"pickup sprite clipped at top");
                if(i<16)b.Save(Path.Combine(path,"frog-pickup-"+i+".png"),ImageFormat.Png);
            }
        }
        Assert(hashes.Count>=6,"pickup is a static image");e.Step(.5);Assert(frog.Dragging,"pickup loop ended while mouse held");
        e.EndDrag(frog);Assert(!frog.Dragging&&frog.State=="drop","release skipped landing");e.Step(.5);Assert(frog.State=="idle","landing did not return to idle");
        Assert(e.Audio.ResourceCount==14&&e.Audio.Emitted==0,"self-test played sound or missing sound data");
        e.Audio.Enabled=true;e.Audio.Volume=25;
        int n=e.Audio.Accepted;e.Time+=2;e.PlayCues("hammer",2.2,2.5);Assert(e.Audio.Accepted==n+1&&e.Audio.LastSound=="thud","hammer impact cue out of sync");
        e.Time+=2;e.PlayCues("hammer",2.5,2.6);Assert(e.Audio.Accepted==n+1,"sound cue repeated every tick");
        e.Audio.Enabled=false;e.Time+=2;e.Audio.Play("croak",e.Time);Assert(e.Audio.Accepted==n+1,"mute ignored");
        e.Audio.Enabled=true;e.Audio.Volume=0;e.Audio.Play("croak",e.Time);Assert(e.Audio.Accepted==n+1,"zero volume ignored");
        e.Audio.Volume=999;Assert(e.Audio.Volume==100,"volume above limit");e.Audio.Volume=-5;Assert(e.Audio.Volume==0,"negative volume accepted");e.Audio.Volume=25;
        foreach(string key in Engine.SoloKinds)Assert(SoundCues.All.ContainsKey(key),"no solo sound plan: "+key);
        foreach(string key in Engine.PairKinds)Assert(SoundCues.All.ContainsKey(key),"no pair sound plan: "+key);
        // Paused animations do not advance cues or generate repeated audio.
        e.Request("hammer");while(e.Gathering)e.Step(.1);e.PairAge=2.3;e.Paused=true;n=e.Audio.Accepted;e.Step(.2);
        Assert(e.PairAge==2.3&&n==e.Audio.Accepted,"paused action advanced sound");e.Paused=false;
        e.Thor.MenuHeld=true;e.Step(.2);Assert(e.PairAge==2.3&&n==e.Audio.Accepted,"open menu advanced sound");e.Thor.MenuHeld=false;e.CancelPair();
    }

    public static void Run(string path){
        Directory.CreateDirectory(path);
        using(var e=new Engine(true)){
            e.AutoWalk=false;e.AutoPair=false;e.AutoSolo=false;e.Scale=1;
            foreach(Pet p in new[]{e.Loki,e.Thor})foreach(string state in new[]{"idle","walk","sleep","react"}){p.State=state;using(var image=e.PetFrame(p))Assert(Visible(image)>100,"missing render "+state);}
            foreach(string pair in Engine.PairKinds){
                e.Request(pair);int steps=0;while(e.Gathering&&steps++<300)e.Step(1.0/12);Assert(!e.Gathering,"gather timeout "+pair);
                for(int i=0;i<Engine.PairSeconds(pair)*Engine.PairFps(pair);i++){e.PairAge=i/(double)Engine.PairFps(pair);using(var frame=e.PairFrame()){Assert(Visible(frame)>100,"empty frame "+pair+i);if(i%12==0)frame.Save(Path.Combine(path,pair+"-"+(i/12)+".png"),ImageFormat.Png);}}
                e.PairAge=0;for(int i=0;i<(Engine.PairSeconds(pair)+1)*12;i++)e.Step(1.0/12);Assert(e.Pair=="","sequence not released "+pair);
            }
            foreach(string action in Engine.SoloKinds){
                e.RequestSolo(action);int step=0;while(e.SoloGathering&&step++<500)e.Step(1.0/12);Assert(!e.SoloGathering,"solo gather timeout "+action);
                for(int i=0;i<Engine.SoloSeconds(action)*24;i++){e.SoloAge=i/24.0;using(var image=e.SoloFrame())Assert(Visible(image)>100,"empty solo "+action+i);}
                e.SoloAge=0;for(int i=0;i<(Engine.SoloSeconds(action)+1)*12;i++)e.Step(1.0/12);Assert(e.Solo=="","solo not released "+action);
            }
            e.Request("hammer");e.CancelPair();Assert(e.Pair==""&&!e.Gathering,"cancel must restore independent pets");
            e.Loki.State="walk";e.Loki.Until=e.Time+1000;e.AutoWalk=true;for(int i=0;i<1200;i++)e.Step(1.0/12);
            var bounds=Screen.FromPoint(new Point((int)e.Loki.X+e.Loki.Width/2,(int)e.Loki.Ground-40)).WorkingArea;
            Assert(e.Loki.X>=bounds.Left&&e.Loki.X+e.Loki.Width<=bounds.Right,"walk boundary");
            double t=e.Time;e.Paused=true;e.Step(1);Assert(t==e.Time,"pause advanced time");e.Paused=false;
            e.Scale=3;e.Clamp(e.Loki);bounds=Screen.FromPoint(new Point((int)e.Loki.X+e.Loki.Width*e.Scale/2,(int)e.Loki.Ground-40)).WorkingArea;Assert(e.Loki.X+e.Loki.Width*e.Scale<=bounds.Right,"resized pet escaped screen");
            // Native renderer contact sheet for the new walking and resting assets.
            using(var contact=SpriteLibrary.Canvas(800,390))using(var g=Graphics.FromImage(contact)){
                g.Clear(Color.FromArgb(233,239,234));SpriteLibrary.Setup(g);int slot=0;
                foreach(string state in new[]{"idle","walk","sleep","react"})foreach(Pet p in new[]{e.Loki,e.Thor}){p.State=state;p.Left=false;p.Age=.3;using(var frame=e.PetFrame(p))g.DrawImageUnscaled(frame,(slot%4)*200,(slot/4)*130);slot++;}
                contact.Save(Path.Combine(path,"native-contact.png"),ImageFormat.Png);
            }
            PolicyChecks(e);NewChecks(e,path);
            File.WriteAllText(Path.Combine(path,"self-test.txt"),"PASS\r\nChecks="+checks+"\r\nEmbedded PNG assets=454; WAV effects=14\r\nCovered: pose rendering, all twelve paired and twenty-four solo interactions, nonempty timeline frames, gathering, release, interruption, boundary after walking, pause, resize, proximity-only pair trigger, cooldown, per-pet solo timers, menu/sleep guards, uniform selection and manual seeking.\r\nAdditional checks: both pets reach both work-area edges at 1x and 2x, rests preserve route, explicit turn, animated frog pickup and landing, embedded WAV headers, sparse cue crossing, mute, volume, pause/menu sound guards. Native per-pixel transparency receives an additional startup smoke check.\r\n");
        }
    }
}
}

