#requires -Version 5.1
<# Clean Ultimate MAX PRO++ 2.1 / Netteria.NET
Windows PowerShell 5.1, .NET Framework, Windows 10 / 11.
Build: .\build-clean-ultimate-max-proplus.ps1
SelfTest deletes only generated test fixtures; SmokeTest renders without cleaning.
#>
[CmdletBinding()]
param([switch]$SelfTest, [switch]$SmokeTest, [string]$TestOutput = '', [double]$TestScale = 1.0, [ValidateSet('pl','en')][string]$Language = 'pl')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$source = @'
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Drawing;
using System.Windows.Forms;
using System.ComponentModel;
using System.Collections.Generic;
using System.Security.Principal;
using System.Runtime.InteropServices;
namespace CleanMax {
public sealed class Category {
    public string Name, Group, Description; public bool Recommended, Admin; public int AgeDays;
    public readonly List<string> Roots=new List<string>();
    public Category(string group,string name,string description,bool recommended,bool admin,int age,params string[] roots) {
        Group=group; Name=name; Description=description; Recommended=recommended; Admin=admin; AgeDays=age;
        Roots.AddRange(roots.Where(p=>!String.IsNullOrWhiteSpace(p)).Distinct(StringComparer.OrdinalIgnoreCase));
    }
}
public sealed class Candidate { public string Path,Root; public long Length; public DateTime Modified; }
public sealed class Result { public List<Candidate> Files=new List<Candidate>(); public long Bytes; public int Skipped,Deleted; public bool Cancelled; }
public static class Engine {
    public static bool Admin { get { using(var id=WindowsIdentity.GetCurrent()) return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator); } }
    public static string Size(long bytes) { string[] units={"B","KB","MB","GB","TB"}; double n=bytes; int i=0; while(n>=1024 && i<4) { n/=1024; i++; } return n.ToString(i==0?"0":"0.0")+" "+units[i]; }
    // Reject drive roots and all reparse points, including ancestors of a cache.
    public static bool SafeRoot(string root) {
        if(String.IsNullOrWhiteSpace(root) || !Path.IsPathRooted(root)) return false;
        string full=Path.GetFullPath(root).TrimEnd('\\'); if(full.Length<=Path.GetPathRoot(full).Length) return false;
        var d=new DirectoryInfo(full); while(d!=null) { if(d.Exists && (d.Attributes&FileAttributes.ReparsePoint)!=0) return false; d=d.Parent; } return true;
    }
    public static bool Inside(string path,string root) { return Path.GetFullPath(path).StartsWith(Path.GetFullPath(root).TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase); }
    public static Result Scan(IEnumerable<Category> categories,Func<bool> cancel,Action<string> log) {
        var result=new Result(); var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var category in categories) {
            if(cancel()) { result.Cancelled=true; break; }
            if(category.Admin && !Admin) { result.Skipped++; log(I18n.T("Pominięto: ")+I18n.T(category.Name)+I18n.T(" — wymagany administrator.")); continue; }
            log(I18n.T("Analiza: ")+I18n.T(category.Name));
            foreach(string root in category.Roots) {
                if(!Directory.Exists(root)) continue;
                try {
                    if(!SafeRoot(root)) { result.Skipped++; log(I18n.T("Pominięto dowiązanie: ")+root); continue; }
                    var pending=new Stack<string>(); pending.Push(root);
                    while(pending.Count>0) {
                        if(cancel()) { result.Cancelled=true; return result; }
                        string dir=pending.Pop();
                        try {
                            if(!SafeRoot(dir)) { result.Skipped++; continue; }
                            foreach(var file in new DirectoryInfo(dir).EnumerateFiles()) {
                                if(cancel()) { result.Cancelled=true; return result; }
                                try {
                                    if((file.Attributes&FileAttributes.ReparsePoint)!=0) { result.Skipped++; continue; }
                                    if(file.LastWriteTimeUtc>DateTime.UtcNow.AddDays(-category.AgeDays)) continue;
                                    if(Inside(file.FullName,root) && seen.Add(file.FullName)) { var f=new Candidate {Path=file.FullName,Root=root,Length=file.Length,Modified=file.LastWriteTimeUtc}; result.Files.Add(f); result.Bytes+=f.Length; }
                                } catch(Exception e) { result.Skipped++; log(I18n.T("Pominięto plik: ")+file.FullName+" — "+e.Message); }
                            }
                            foreach(string child in Directory.EnumerateDirectories(dir)) {
                                if((File.GetAttributes(child)&FileAttributes.ReparsePoint)==0) pending.Push(child);
                                else { result.Skipped++; log(I18n.T("Pominięto dowiązanie: ")+child); }
                            }
                        } catch(Exception e) { result.Skipped++; log(I18n.T("Brak dostępu: ")+dir+" — "+e.Message); }
                    }
                } catch(Exception e) { result.Skipped++; log(I18n.T("Pominięto: ")+root+" — "+e.Message); }
            }
        }
        return result;
    }
    public static Result Clean(Result scan,Func<bool> cancel,Action<string> log,Action<int> progress) {
        var result=new Result(); int i=0;
        foreach(var item in scan.Files) {
            if(cancel()) { result.Cancelled=true; break; }
            try {
                // Delete files only, rechecking scope, links and metadata immediately before deletion.
                if(!Inside(item.Path,item.Root) || !SafeRoot(item.Root) || !SafeRoot(Path.GetDirectoryName(item.Path))) throw new IOException(I18n.T("Ścieżka poza zakresem lub dowiązanie."));
                var f=new FileInfo(item.Path);
                if(!f.Exists || (f.Attributes&FileAttributes.ReparsePoint)!=0 || f.Length!=item.Length || f.LastWriteTimeUtc!=item.Modified) throw new IOException(I18n.T("Plik zmienił się od czasu analizy albo już nie istnieje."));
                f.Delete(); result.Deleted++; result.Bytes+=item.Length;
            } catch(Exception e) { result.Skipped++; log(I18n.T("Pominięto: ")+item.Path+" — "+e.Message); }
            i++; if(i%50==0 || i==scan.Files.Count) progress(i*100/Math.Max(1,scan.Files.Count));
        }
        return result;
    }
    static string[] Children(string path) {
        try { if(Directory.Exists(path) && SafeRoot(path)) return Directory.GetDirectories(path).Where(SafeRoot).ToArray(); }
        catch(IOException) {} catch(UnauthorizedAccessException) {} return new string[0];
    }
    static string[] BrowserRoots(string path) {
        var roots=new List<string>(); foreach(string profile in Children(path)) {
            string name=Path.GetFileName(profile); if(name!="Default" && !name.StartsWith("Profile ",StringComparison.OrdinalIgnoreCase)) continue;
            foreach(string cache in new[]{"Cache","Code Cache","GPUCache"}) roots.Add(Path.Combine(profile,cache));
        } return roots.ToArray();
    }
    public static List<Category> Catalog() {
        string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),win=Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var list=new List<Category>();
        list.Add(new Category("System","Pliki tymczasowe użytkownika","Pliki starsze niż 24 godziny. Używane pliki zostaną pominięte.",true,false,1,Path.Combine(local,"Temp")));
        list.Add(new Category("System","Pliki tymczasowe Windows","Pliki starsze niż 7 dni. Wymaga uruchomienia jako administrator.",false,true,7,Path.Combine(win,"Temp")));
        list.Add(new Category("System","Zrzuty awarii","Pliki diagnostyczne starsze niż 7 dni; mogą być potrzebne do analizy awarii.",false,false,7,Path.Combine(local,"CrashDumps")));
        list.Add(new Category("Aplikacje","Pliki tymczasowe aplikacji Store","Tylko TempState. Dane aplikacji, ustawienia i instalacje pozostają zachowane.",false,false,1,Children(Path.Combine(local,"Packages")).Select(p=>Path.Combine(p,"TempState")).ToArray()));
        list.Add(new Category("Aplikacje","Pamięć podręczna NetBeans","Zamknij NetBeans przed czyszczeniem. Tylko katalogi Cache.",false,false,1,Children(Path.Combine(local,"NetBeans")).Select(p=>Path.Combine(p,"Cache")).ToArray()));
        list.Add(new Category("Programowanie","Pamięć podręczna npm","Tylko _cacache i _logs. Zachowuje instalacje Node.js i nvm.",false,false,1,Path.Combine(local,"npm-cache","_cacache"),Path.Combine(local,"npm-cache","_logs")));
        list.Add(new Category("Programowanie","Pamięć podręczna NuGet","Cache pobrań HTTP. Pakiety projektów i poświadczenia pozostają zachowane.",false,false,1,Path.Combine(local,"NuGet","v3-cache"),Path.Combine(local,"NuGet","Cache")));
        list.Add(new Category("Programowanie","Pamięć podręczna Visual Studio","Tylko ComponentModelCache. Zamknij Visual Studio przed czyszczeniem.",false,false,1,Children(Path.Combine(local,"Microsoft","VisualStudio")).Select(p=>Path.Combine(p,"ComponentModelCache")).ToArray()));
        list.Add(new Category("Programowanie","Pamięć podręczna JetBrains","Tylko caches. Historia lokalna, ustawienia i projekty pozostają zachowane.",false,false,1,Children(Path.Combine(local,"JetBrains")).Select(p=>Path.Combine(p,"caches")).ToArray()));
        foreach(var b in new[]{new[]{"Google Chrome","Google\\Chrome\\User Data"},new[]{"Microsoft Edge","Microsoft\\Edge\\User Data"},new[]{"Brave","BraveSoftware\\Brave-Browser\\User Data"},new[]{"Chromium","Chromium\\User Data"}})
            list.Add(new Category("Przeglądarki",b[0],"Zamknij przeglądarkę. Tylko Cache, Code Cache i GPUCache; bez haseł, historii i cookies.",false,false,1,BrowserRoots(Path.Combine(local,b[1]))));
        return list;
    }
}
public static class I18n {
    public static bool English;
    public static string Pick(string pl,string en) { return English?en:pl; }
    static readonly Dictionary<string,string> EnglishText=new Dictionary<string,string> {
        {"System","System"},{"Aplikacje","Applications"},{"Programowanie","Development"},{"Przeglądarki","Browsers"},
        {"Pliki tymczasowe użytkownika","User temporary files"},{"Pliki tymczasowe Windows","Windows temporary files"},{"Zrzuty awarii","Crash dumps"},
        {"Pliki tymczasowe aplikacji Store","Microsoft Store temporary files"},{"Pamięć podręczna NetBeans","NetBeans cache"},{"Pamięć podręczna npm","npm cache"},{"Pamięć podręczna NuGet","NuGet cache"},{"Pamięć podręczna Visual Studio","Visual Studio cache"},{"Pamięć podręczna JetBrains","JetBrains cache"},
        {"Pliki starsze niż 24 godziny. Używane pliki zostaną pominięte.","Files older than 24 hours. Files in use will be skipped."},
        {"Pliki starsze niż 7 dni. Wymaga uruchomienia jako administrator.","Files older than 7 days. Requires running as administrator."},
        {"Pliki diagnostyczne starsze niż 7 dni; mogą być potrzebne do analizy awarii.","Diagnostic files older than 7 days; these may be needed to investigate crashes."},
        {"Tylko TempState. Dane aplikacji, ustawienia i instalacje pozostają zachowane.","TempState only. App data, settings and installations are preserved."},
        {"Zamknij NetBeans przed czyszczeniem. Tylko katalogi Cache.","Close NetBeans before cleaning. Only Cache folders are included."},
        {"Tylko _cacache i _logs. Zachowuje instalacje Node.js i nvm.","Only _cacache and _logs. Node.js and nvm installations are preserved."},
        {"Cache pobrań HTTP. Pakiety projektów i poświadczenia pozostają zachowane.","HTTP download cache. Project packages and credentials are preserved."},
        {"Tylko ComponentModelCache. Zamknij Visual Studio przed czyszczeniem.","ComponentModelCache only. Close Visual Studio before cleaning."},
        {"Tylko caches. Historia lokalna, ustawienia i projekty pozostają zachowane.","Only caches. Local history, settings and projects are preserved."},
        {"Zamknij przeglądarkę. Tylko Cache, Code Cache i GPUCache; bez haseł, historii i cookies.","Close the browser. Only Cache, Code Cache and GPUCache; passwords, history and cookies are preserved."},
        {"Pominięto: ","Skipped: "},{" — wymagany administrator."," — administrator rights required."},{"Analiza: ","Scanning: "},{"Pominięto dowiązanie: ","Skipped link: "},{"Pominięto plik: ","Skipped file: "},{"Brak dostępu: ","Access denied: "},
        {"Ścieżka poza zakresem lub dowiązanie.","Path is outside the allowed scope or is a link."},{"Plik zmienił się od czasu analizy albo już nie istnieje.","The file has changed since the scan or no longer exists."}
    };
    public static string T(string text) { string translated; return English && EnglishText.TryGetValue(text,out translated)?translated:text; }
}
public sealed class DarkButton : Button {
    bool hover;
    protected override void OnMouseEnter(EventArgs e) { hover=true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover=false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnPaint(PaintEventArgs e) {
        Color bg=Enabled?(hover?ControlPaint.Light(BackColor,.18f):BackColor):Color.FromArgb(32,38,53);
        using(var brush=new SolidBrush(bg)) e.Graphics.FillRectangle(brush,ClientRectangle);
        TextRenderer.DrawText(e.Graphics,Text,Font,ClientRectangle,Enabled?ForeColor:Color.FromArgb(148,161,184),TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
        if(Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics,Rectangle.Inflate(ClientRectangle,-4,-4),ForeColor,bg);
    }
}
public sealed class DarkCheckBox : CheckBox {
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(BackColor); int size=Math.Max(18,Font.Height-3),y=(Height-size)/2;
        Color ink=Enabled?ForeColor:Color.FromArgb(169,183,204);
        using(var brush=new SolidBrush(Checked?Color.FromArgb(116,88,240):Color.FromArgb(30,37,53))) e.Graphics.FillRectangle(brush,0,y,size,size);
        using(var pen=new Pen(ink,1)) e.Graphics.DrawRectangle(pen,0,y,size,size);
        if(Checked) using(var pen=new Pen(Color.White,2)) { e.Graphics.DrawLine(pen,4,y+size/2,size/2-1,y+size-4); e.Graphics.DrawLine(pen,size/2-1,y+size-4,size-3,y+4); }
        TextRenderer.DrawText(e.Graphics,Text,Font,new Rectangle(size+12,0,Width-size-12,Height),ink,TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
        if(Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics,Rectangle.Inflate(ClientRectangle,-2,-2),ink,BackColor);
    }
}
// Fully drawn scrollbars; no undocumented Windows dark-mode ordinals or native light tracks.
public sealed class DarkScrollBar : Control {
    public event EventHandler ValueChanged;
    int maximum,viewport=1,value,dragOffset; bool dragging;
    public int Maximum { get { return maximum; } }
    public int Value { get { return value; } set { int next=Math.Max(0,Math.Min(maximum,value)); if(next==this.value) return; this.value=next; Invalidate(); if(ValueChanged!=null) ValueChanged(this,EventArgs.Empty); } }
    public DarkScrollBar() { SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.UserPaint|ControlStyles.Selectable,true); Width=16; TabStop=true; BackColor=Color.FromArgb(22,28,41); AccessibleRole=AccessibleRole.ScrollBar; }
    public void SetRange(int content,int page) { viewport=Math.Max(1,page); maximum=Math.Max(0,content-viewport); Value=value; Invalidate(); }
    Rectangle Thumb { get { int h=maximum==0?Height:Math.Min(Height,Math.Max(30,(int)((long)Height*viewport/(maximum+viewport)))); return new Rectangle(3,maximum==0?0:(int)((long)value*(Height-h)/maximum),Math.Max(3,Width-6),h); } }
    protected override void OnPaint(PaintEventArgs e) { e.Graphics.Clear(BackColor); if(maximum>0) using(var b=new SolidBrush(dragging?Color.FromArgb(148,128,255):Color.FromArgb(95,109,139))) e.Graphics.FillRectangle(b,Thumb); if(Focused) ControlPaint.DrawFocusRectangle(e.Graphics,ClientRectangle); }
    protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if(e.Button!=MouseButtons.Left) return; Focus(); if(Thumb.Contains(e.Location)) { dragging=true; dragOffset=e.Y-Thumb.Y; Capture=true; } else Value+=e.Y<Thumb.Y?-viewport:viewport; Invalidate(); }
    protected override void OnMouseMove(MouseEventArgs e) { base.OnMouseMove(e); if(dragging && Height>Thumb.Height) Value=(int)((long)(e.Y-dragOffset)*maximum/(Height-Thumb.Height)); }
    protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); dragging=false; Capture=false; Invalidate(); }
    protected override void OnMouseCaptureChanged(EventArgs e) { if(!Capture) dragging=false; base.OnMouseCaptureChanged(e); }
    protected override void OnMouseWheel(MouseEventArgs e) { Value-=e.Delta/120*Math.Max(1,viewport/6); base.OnMouseWheel(e); }
    protected override bool IsInputKey(Keys key) { return key==Keys.Up||key==Keys.Down||key==Keys.PageUp||key==Keys.PageDown||key==Keys.Home||key==Keys.End||base.IsInputKey(key); }
    protected override void OnKeyDown(KeyEventArgs e) { switch(e.KeyCode) { case Keys.Up: Value-=Math.Max(1,viewport/10); break; case Keys.Down: Value+=Math.Max(1,viewport/10); break; case Keys.PageUp: Value-=viewport; break; case Keys.PageDown: Value+=viewport; break; case Keys.Home: Value=0; break; case Keys.End: Value=maximum; break; default: base.OnKeyDown(e); return; } e.Handled=true; }
}
public sealed class DarkScrollPanel : UserControl {
    readonly Panel viewport=new Panel(); public readonly Panel Content=new Panel(); public readonly DarkScrollBar Bar=new DarkScrollBar();
    public DarkScrollPanel() { Bar.Dock=DockStyle.Right; viewport.Dock=DockStyle.Fill; viewport.Controls.Add(Content); Controls.Add(viewport); Controls.Add(Bar); Bar.ValueChanged+=delegate { Content.Top=-Bar.Value; }; viewport.SizeChanged+=delegate { Content.Width=viewport.ClientSize.Width; Bar.SetRange(Content.Height,viewport.Height); }; MouseWheel+=Wheel; viewport.MouseWheel+=Wheel; }
    void Wheel(object sender,MouseEventArgs e) { Bar.Value-=e.Delta/120*60; }
    public void Watch(Control control) { control.MouseWheel+=Wheel; control.Enter+=delegate { var point=Content.PointToClient(control.PointToScreen(Point.Empty)); if(point.Y<Bar.Value) Bar.Value=point.Y; else if(point.Y+control.Height>Bar.Value+viewport.Height) Bar.Value=point.Y+control.Height-viewport.Height; }; foreach(Control child in control.Controls) Watch(child); }
    public void SetHeight(int height) { Content.Height=Math.Max(0,height); Content.Width=viewport.ClientSize.Width; Bar.SetRange(height,viewport.ClientSize.Height); Content.Top=-Bar.Value; }
}
public sealed class ObservedTextBox : TextBox {
    public event EventHandler ViewChanged;
    protected override void WndProc(ref Message m) { base.WndProc(ref m); if((m.Msg==0x20a||m.Msg==0x101||m.Msg==0x115||m.Msg==5) && ViewChanged!=null) ViewChanged(this,EventArgs.Empty); }
}
public sealed class DarkLog : UserControl {
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr handle,int message,IntPtr wparam,IntPtr lparam);
    readonly ObservedTextBox box=new ObservedTextBox(); public readonly DarkScrollBar Bar=new DarkScrollBar(); bool syncing;
    public DarkLog() {
        box.Dock=DockStyle.Fill; box.Multiline=true; box.ReadOnly=true; box.WordWrap=true; box.ScrollBars=ScrollBars.None; box.BorderStyle=BorderStyle.None;
        box.BackColor=Color.FromArgb(27,33,47); box.ForeColor=Color.FromArgb(180,193,214); box.Font=new Font("Consolas",10); Bar.Dock=DockStyle.Right; Controls.Add(box); Controls.Add(Bar);
        box.TextChanged+=delegate { Sync(); }; box.ViewChanged+=delegate { Sync(); };
        Bar.ValueChanged+=delegate { if(!syncing && box.IsHandleCreated) SendMessage(box.Handle,0xb6,IntPtr.Zero,new IntPtr(Bar.Value-FirstLine)); };
    }
    int FirstLine { get { return (int)SendMessage(box.Handle,0xce,IntPtr.Zero,IntPtr.Zero); } }
    void Sync() { if(syncing || !box.IsHandleCreated) return; syncing=true; try { int lines=(int)SendMessage(box.Handle,0xba,IntPtr.Zero,IntPtr.Zero); int page=Math.Max(1,box.ClientSize.Height/box.Font.Height); Bar.SetRange(lines,page); Bar.Value=FirstLine; } finally { syncing=false; } }
    public override string Text { get { return box.Text; } set { box.Text=value; } }
    public void AppendLine(string line) { if(box.TextLength>180000) { box.Select(0,60000); box.SelectedText=""; } box.AppendText(line+Environment.NewLine); box.SelectionStart=box.TextLength; box.ScrollToCaret(); Sync(); }
}
public sealed class MainWindow : Form {
    static readonly Color Bg=Color.FromArgb(18,22,32),Card=Color.FromArgb(27,33,47),Raised=Color.FromArgb(38,46,64),Ink=Color.FromArgb(242,246,255),Muted=Color.FromArgb(180,193,214),Accent=Color.FromArgb(116,88,240);
    readonly List<Category> catalog; readonly Dictionary<CheckBox,Category> choices=new Dictionary<CheckBox,Category>(); readonly Dictionary<Control,string[]> translations=new Dictionary<Control,string[]>(); readonly Dictionary<Category,Label> descriptions=new Dictionary<Category,Label>(); readonly List<Button> navButtons=new List<Button>();
    readonly DarkScrollPanel categories=new DarkScrollPanel(); readonly Label total=new Label(),selection=new Label(),state=new Label(),heading=new Label(); readonly DarkLog log=new DarkLog();
    readonly Button analyze,clean,cancel,select,recommended,export,elevate,polish,english; readonly ProgressBar progress=new ProgressBar();
    BackgroundWorker worker; Result scan,lastResult; string activeGroup="System"; bool busy,changing,resizing,lastCleaning; string[] status={"Gotowe do analizy. Pliki nie będą jeszcze usuwane.","Ready to scan. No files will be deleted yet."};
    static string L(string pl,string en) { return I18n.Pick(pl,en); }
    void Bind(Control control,string pl,string en) { translations[control]=new[]{pl,en}; control.Text=L(pl,en); }
    Label Label(string pl,string en,float size,Color color,bool bold) { var label=new Label {Dock=DockStyle.Fill,ForeColor=color,Font=new Font("Segoe UI",size,bold?FontStyle.Bold:FontStyle.Regular),TextAlign=ContentAlignment.MiddleLeft}; Bind(label,pl,en); return label; }
    Button Button(string pl,string en,int width) { var b=new DarkButton {Width=width,Height=44,Font=new Font("Segoe UI",10.5f),FlatStyle=FlatStyle.Flat,BackColor=Raised,ForeColor=Ink,Cursor=Cursors.Hand,Margin=new Padding(0,4,8,4),UseVisualStyleBackColor=false}; b.FlatAppearance.BorderSize=0; Bind(b,pl,en); return b; }
    public MainWindow() {
        catalog=Engine.Catalog(); Text="Clean Ultimate MAX PRO++ | Netteria.NET"; BackColor=Bg; ForeColor=Ink; Font=new Font("Segoe UI",11);
        AutoScaleDimensions=new SizeF(96,96); AutoScaleMode=AutoScaleMode.Dpi; ClientSize=new Size(1320,900); MinimumSize=new Size(1120,760); StartPosition=FormStartPosition.CenterScreen;
        try { Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch {}
        var root=new TableLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(28,22,28,18),ColumnCount=1,RowCount=6};
        foreach(int h in new[]{92,60,70}) root.RowStyles.Add(new RowStyle(SizeType.Absolute,h)); root.RowStyles.Add(new RowStyle(SizeType.Percent,100)); foreach(int h in new[]{44,60}) root.RowStyles.Add(new RowStyle(SizeType.Absolute,h)); root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); Controls.Add(root);
        var header=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=2,Margin=Padding.Empty}; header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,310)); header.RowStyles.Add(new RowStyle(SizeType.Absolute,45)); header.RowStyles.Add(new RowStyle(SizeType.Absolute,35));
        header.Controls.Add(Label("Clean Ultimate MAX PRO++","Clean Ultimate MAX PRO++",26,Ink,true),0,0); header.Controls.Add(Label("Porządek na dysku. Kontrola nad tym, co usuwasz.","A cleaner drive. You control what gets deleted.",12,Muted,false),0,1);
        var languages=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft,WrapContents=false,Margin=Padding.Empty}; english=Button("English","English",100); polish=Button("Polski","Polski",100); english.Height=38; polish.Height=38; languages.Controls.Add(english); languages.Controls.Add(polish); header.Controls.Add(languages,1,0);
        polish.Click+=delegate { SetLanguage(false); }; english.Click+=delegate { SetLanguage(true); };
        var brand=new LinkLabel {Text="Netteria.NET  ↗",Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleRight,LinkColor=Muted,ActiveLinkColor=Ink,VisitedLinkColor=Muted}; brand.LinkClicked+=delegate { try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("https://netteria.net") {UseShellExecute=true}); } catch(Exception e) { Append(e.Message); } }; header.Controls.Add(brand,1,1); root.Controls.Add(header,0,0);
        var nav=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false,Margin=Padding.Empty}; foreach(string group in new[]{"System","Aplikacje","Programowanie","Przeglądarki"}) { var btn=Button(group,group,170); btn.Tag=group; btn.Font=new Font("Segoe UI",11,FontStyle.Bold); btn.Click+=delegate(object sender,EventArgs e) { ShowGroup((string)((Button)sender).Tag); }; nav.Controls.Add(btn); navButtons.Add(btn); } root.Controls.Add(nav,0,1);
        var permission=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,BackColor=Card,Padding=new Padding(12,6,12,6),Margin=new Padding(0,0,0,12)}; permission.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); permission.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,280));
        permission.Controls.Add(Label(Engine.Admin?"Uprawnienia administratora aktywne. Pliki tymczasowe Windows są dostępne.":"Pliki tymczasowe Windows wymagają uprawnień administratora.",Engine.Admin?"Administrator access enabled. Windows temporary files are available.":"Windows temporary files require administrator access.",11,Muted,false),0,0);
        elevate=Button("Uruchom jako administrator","Run as administrator",272); elevate.Enabled=!Engine.Admin; elevate.Margin=Padding.Empty; permission.Controls.Add(elevate,1,0); root.Controls.Add(permission,0,2); elevate.Click+=delegate { Elevate(); };
        var body=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Margin=Padding.Empty}; body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,60)); body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,40)); body.RowStyles.Add(new RowStyle(SizeType.Percent,100)); root.Controls.Add(body,0,3);
        var left=new TableLayoutPanel {Dock=DockStyle.Fill,BackColor=Card,Padding=new Padding(20),ColumnCount=1,RowCount=3,Margin=new Padding(0,0,14,0)}; left.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); left.RowStyles.Add(new RowStyle(SizeType.Absolute,42)); left.RowStyles.Add(new RowStyle(SizeType.Percent,100)); left.RowStyles.Add(new RowStyle(SizeType.Absolute,56)); heading.Font=new Font("Segoe UI",16,FontStyle.Bold); heading.Dock=DockStyle.Fill; left.Controls.Add(heading,0,0);
        categories.Dock=DockStyle.Fill; categories.Margin=Padding.Empty; left.Controls.Add(categories,0,1);
        foreach(var category in catalog) {
            var item=new Panel {Height=112,Width=620,Margin=new Padding(0,0,0,10),BackColor=Raised,Tag=category};
            var cb=new DarkCheckBox {Text=I18n.T(category.Name),Checked=category.Recommended,Font=new Font("Segoe UI",12,FontStyle.Bold),FlatStyle=FlatStyle.Flat,ForeColor=Ink,Location=new Point(14,10),Size=new Size(588,34),Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right,Tag=category}; cb.Enabled=!category.Admin||Engine.Admin;
            var desc=new Label {Text=I18n.T(category.Description),ForeColor=Muted,Location=new Point(46,48),Size=new Size(558,58),Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right,Font=new Font("Segoe UI",10.5f)}; cb.CheckedChanged+=delegate { if(!changing) InvalidateScan(); }; item.Controls.Add(cb); item.Controls.Add(desc); choices.Add(cb,category); descriptions.Add(category,desc); categories.Content.Controls.Add(item); categories.Watch(item);
        }
        categories.SizeChanged+=delegate { ResizeCards(); };
        var actions=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false,Margin=new Padding(0,8,0,0)}; select=Button("Zaznacz wszystkie kategorie","Select all categories",302); recommended=Button("Zalecane","Recommended",145); actions.Controls.Add(select); actions.Controls.Add(recommended);
        select.Click+=delegate { var available=choices.Keys.Where(c=>!choices[c].Admin||Engine.Admin).ToArray(); bool all=available.All(c=>c.Checked); changing=true; foreach(var c in available) c.Checked=!all; changing=false; InvalidateScan(); };
        recommended.Click+=delegate { changing=true; foreach(var c in choices.Keys) c.Checked=choices[c].Recommended&&(!choices[c].Admin||Engine.Admin); changing=false; InvalidateScan(); }; left.Controls.Add(actions,0,2); body.Controls.Add(left,0,0);
        var right=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=1,RowCount=7,BackColor=Card,Padding=new Padding(20),Margin=Padding.Empty}; right.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); foreach(int h in new[]{32,63,38,72,38}) right.RowStyles.Add(new RowStyle(SizeType.Absolute,h)); right.RowStyles.Add(new RowStyle(SizeType.Percent,100)); right.RowStyles.Add(new RowStyle(SizeType.Absolute,52));
        right.Controls.Add(Label("PODSUMOWANIE ANALIZY","SCAN SUMMARY",10,Muted,true),0,0); total.ForeColor=Ink; total.Font=new Font("Segoe UI",32,FontStyle.Bold); total.Dock=DockStyle.Fill; right.Controls.Add(total,0,1); selection.Dock=DockStyle.Fill; selection.ForeColor=Muted; right.Controls.Add(selection,0,2);
        right.Controls.Add(Label("Najpierw przeanalizuj wybrane obszary.\r\nPrzed usunięciem zobaczysz podsumowanie.","Scan your selected areas first.\r\nReview the results before deleting files.",11,Muted,false),0,3); right.Controls.Add(Label("Dziennik operacji","Activity log",12,Ink,true),0,4); log.Dock=DockStyle.Fill; right.Controls.Add(log,0,5);
        export=Button("Zapisz dziennik…","Save log…",185); export.Click+=delegate { using(var dialog=new SaveFileDialog {Filter=L("Plik tekstowy|*.txt","Text file|*.txt"),FileName="CleanMax-log.txt"}) if(dialog.ShowDialog(this)==DialogResult.OK) { try { File.WriteAllText(dialog.FileName,log.Text,Encoding.UTF8); } catch(Exception e) { MessageBox.Show(this,e.Message,Text); } } }; right.Controls.Add(export,0,6); body.Controls.Add(right,1,0);
        state.Dock=DockStyle.Fill; state.TextAlign=ContentAlignment.MiddleLeft; state.ForeColor=Muted; root.Controls.Add(state,0,4);
        var footer=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=4,RowCount=1,Margin=Padding.Empty}; footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); foreach(int w in new[]{125,180,210}) footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,w)); progress.Dock=DockStyle.Fill; progress.Visible=false; progress.Margin=new Padding(0,18,24,18); footer.Controls.Add(progress,0,0);
        cancel=Button("Przerwij","Cancel",113); analyze=Button("Analizuj","Scan",168); clean=Button("Wyczyść","Clean",198); cancel.Enabled=false; clean.Enabled=false; clean.BackColor=Accent; footer.Controls.Add(cancel,1,0); footer.Controls.Add(analyze,2,0); footer.Controls.Add(clean,3,0); root.Controls.Add(footer,0,5);
        cancel.Click+=delegate { if(worker!=null&&worker.IsBusy) { worker.CancelAsync(); cancel.Enabled=false; Status("Zatrzymywanie…","Stopping…"); } }; analyze.Click+=delegate { Start(false); };
        clean.Click+=delegate { if(scan!=null&&scan.Files.Count>0&&ConfirmCleaning()) Start(true); };
        FormClosing+=delegate(object sender,FormClosingEventArgs e) { if(busy) { e.Cancel=true; worker.CancelAsync(); Status("Zatrzymywanie… Po zakończeniu zamknij okno.","Stopping… Close the window when the operation finishes."); } };
        Shown+=delegate { var area=Screen.FromControl(this).WorkingArea; if(Width>area.Width || Height>area.Height) { MinimumSize=new Size(Math.Min(MinimumSize.Width,area.Width),Math.Min(MinimumSize.Height,area.Height)); Size=new Size(Math.Min(Width,area.Width),Math.Min(Height,area.Height)); Location=new Point(area.Left+(area.Width-Width)/2,area.Top+(area.Height-Height)/2); } ResizeCards(); };
        ShowGroup("System"); SetLanguage(I18n.English); InvalidateScan(); Append(L("Gotowe. Wybierz obszary i kliknij Analizuj.","Ready. Select areas and click Scan."));
    }
    public static System.Diagnostics.ProcessStartInfo ElevationInfo(string executable,string scriptPath,bool english) {
        string args="-Language "+(english?"en":"pl");
        if(!String.IsNullOrEmpty(scriptPath)) { executable=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","WindowsPowerShell","v1.0","powershell.exe"); args="-NoProfile -STA -ExecutionPolicy Bypass -File \""+scriptPath+"\" "+args; }
        return new System.Diagnostics.ProcessStartInfo(executable,args) {UseShellExecute=true,Verb="runas",WorkingDirectory=Path.GetDirectoryName(executable)};
    }
    bool ConfirmCleaning() {
        using(var dialog=new Form {Text=L("Potwierdź czyszczenie","Confirm cleaning"),ClientSize=new Size(580,245),StartPosition=FormStartPosition.CenterParent,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false,ShowInTaskbar=false,BackColor=Card,ForeColor=Ink,Font=new Font("Segoe UI",11),AutoScaleMode=AutoScaleMode.Dpi}) {
            var layout=new TableLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(24),ColumnCount=1,RowCount=2}; layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); layout.RowStyles.Add(new RowStyle(SizeType.Percent,100)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,52)); dialog.Controls.Add(layout);
            layout.Controls.Add(new Label {Dock=DockStyle.Fill,Text=String.Format(L("Usunąć {0} plików ({1})?\n\nZamknij czyszczone aplikacje. Pliki zostaną usunięte trwale, z pominięciem Kosza.","Delete {0} files ({1})?\n\nClose the affected apps. Files will be permanently deleted, bypassing the Recycle Bin."),scan.Files.Count,Engine.Size(scan.Bytes))},0,0);
            var buttons=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft}; var no=new DarkButton {Text=L("Anuluj","Cancel"),Width=150,Height=42,BackColor=Raised,ForeColor=Ink,DialogResult=DialogResult.Cancel}; var yes=new DarkButton {Text=L("Usuń pliki","Delete files"),Width=165,Height=42,BackColor=Accent,ForeColor=Ink,DialogResult=DialogResult.Yes}; buttons.Controls.Add(no); buttons.Controls.Add(yes); layout.Controls.Add(buttons,0,1); dialog.CancelButton=no; dialog.AcceptButton=no;
            return dialog.ShowDialog(this)==DialogResult.Yes;
        }
    }
    void Elevate() { if(busy||Engine.Admin) return; try { using(var process=System.Diagnostics.Process.Start(ElevationInfo(Application.ExecutablePath,App.EntryScript,I18n.English))) { if(process!=null) Close(); } } catch(Win32Exception e) { if(e.NativeErrorCode==1223) Status("Anulowano nadanie uprawnień administratora.","Administrator access was cancelled."); else Append(e.Message); } catch(Exception e) { Append(e.Message); } }
    void SetLanguage(bool englishValue) { if(busy) return; I18n.English=englishValue; foreach(var pair in translations) pair.Key.Text=L(pair.Value[0],pair.Value[1]); foreach(var pair in choices) pair.Key.Text=I18n.T(pair.Value.Name); foreach(var pair in descriptions) pair.Value.Text=I18n.T(pair.Key.Description); foreach(var b in navButtons) b.Text=I18n.T((string)b.Tag); polish.BackColor=englishValue?Raised:Accent; english.BackColor=englishValue?Accent:Raised; heading.Text=I18n.T(activeGroup); UpdateSelectionButton(); RefreshSummary(); state.Text=L(status[0],status[1]); categories.Bar.AccessibleName=L("Przewijanie kategorii","Category scroll"); log.Bar.AccessibleName=L("Przewijanie dziennika","Log scroll"); }
    void Status(string pl,string en) { status=new[]{pl,en}; state.Text=L(pl,en); }
    void UpdateSelectionButton() { if(select==null) return; bool all=choices.Keys.Where(c=>!choices[c].Admin||Engine.Admin).All(c=>c.Checked); select.Text=all?L("Odznacz wszystkie kategorie","Deselect all categories"):L("Zaznacz wszystkie kategorie","Select all categories"); }
    void ResizeCards() { if(resizing) return; resizing=true; try { int y=0; foreach(Control c in categories.Content.Controls) { c.Width=Math.Max(180,categories.Content.ClientSize.Width-8); if(((Category)c.Tag).Group==activeGroup) { c.Location=new Point(0,y); y+=c.Height+c.Margin.Bottom; } else c.Location=Point.Empty; } categories.SetHeight(y); } finally { resizing=false; } }
    void ShowGroup(string group) { activeGroup=group; heading.Text=I18n.T(group); categories.Bar.Value=0; foreach(Control c in categories.Content.Controls) c.Visible=((Category)c.Tag).Group==group; foreach(var b in navButtons) b.BackColor=(string)b.Tag==group?Accent:Bg; ResizeCards(); }
    void RefreshSummary() { if(lastResult==null) { total.Text="—"; selection.Text=L("Wybrano obszarów: ","Selected areas: ")+choices.Keys.Count(c=>c.Checked); } else { total.Text=Engine.Size(lastResult.Bytes); selection.Text=(lastCleaning?L("Zwolnione miejsce • usunięto: ","Space freed • deleted: "):L("Do usunięcia • plików: ","To delete • files: "))+(lastCleaning?lastResult.Deleted:lastResult.Files.Count); } }
    void InvalidateScan() { scan=null; lastResult=null; if(clean!=null) clean.Enabled=false; progress.Value=0; progress.Visible=false; RefreshSummary(); UpdateSelectionButton(); Status("Gotowe do analizy. Pliki nie będą jeszcze usuwane.","Ready to scan. No files will be deleted yet."); }
    void Append(string text) { log.AppendLine(DateTime.Now.ToString("HH:mm:ss")+"  "+text); }
    void SetBusy(bool value) { busy=value; analyze.Enabled=!value; select.Enabled=!value; recommended.Enabled=!value; polish.Enabled=!value; english.Enabled=!value; elevate.Enabled=!value&&!Engine.Admin; cancel.Enabled=value; clean.Enabled=!value&&scan!=null&&scan.Files.Count>0; foreach(var cb in choices.Keys) cb.Enabled=!value&&(!choices[cb].Admin||Engine.Admin); }
    void Start(bool cleaning,Category[] testSelection=null) {
        if(busy) return; var selected=testSelection??choices.Where(p=>p.Key.Checked).Select(p=>p.Value).ToArray(); if(selected.Length==0) { Status("Zaznacz przynajmniej jeden obszar.","Select at least one area."); return; }
        Result previous=scan; if(!cleaning) { scan=null; lastResult=null; total.Text="…"; } SetBusy(true); progress.Value=0; progress.Visible=true; progress.Style=cleaning?ProgressBarStyle.Continuous:ProgressBarStyle.Marquee; Status(cleaning?"Czyszczenie…":"Analizowanie wybranych obszarów…",cleaning?"Cleaning…":"Scanning selected areas…");
        worker=new BackgroundWorker {WorkerReportsProgress=true,WorkerSupportsCancellation=true}; worker.DoWork+=delegate(object sender,DoWorkEventArgs e) { var w=(BackgroundWorker)sender; Action<string> report=s=>w.ReportProgress(-1,s); e.Result=cleaning?Engine.Clean(previous,()=>w.CancellationPending,report,p=>w.ReportProgress(p)):Engine.Scan(selected,()=>w.CancellationPending,report); };
        worker.ProgressChanged+=delegate(object sender,ProgressChangedEventArgs e) { if(e.UserState!=null) Append((string)e.UserState); else progress.Value=Math.Max(0,Math.Min(100,e.ProgressPercentage)); };
        worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e) {
            progress.Style=ProgressBarStyle.Continuous;
            if(e.Error!=null) { scan=null; lastResult=null; Status("Operacja nie powiodła się. Sprawdź dziennik.","The operation failed. Check the log."); Append(e.Error.Message); }
            else { var result=(Result)e.Result; lastResult=result; lastCleaning=cleaning; scan=cleaning||result.Cancelled?null:result; Status((result.Cancelled?"Przerwano. ":cleaning?"Czyszczenie zakończone. ":"Analiza zakończona. ")+"Pominięto: "+result.Skipped+".",(result.Cancelled?"Cancelled. ":cleaning?"Cleaning complete. ":"Scan complete. ")+"Skipped: "+result.Skipped+"."); Append(state.Text+" "+(cleaning?L("Zwolniono: ","Freed: "):L("Znaleziono: ","Found: "))+Engine.Size(result.Bytes)); progress.Value=result.Cancelled?0:100; }
            RefreshSummary(); SetBusy(false); worker.Dispose(); worker=null;
        }; worker.RunWorkerAsync();
    }
    void CapturePreview(string output,string name) { PerformLayout(); ResizeCards(); Refresh(); using(var bitmap=new Bitmap(Width,Height)) { DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height)); bitmap.Save(Path.Combine(output,name+".png")); } }
    void Assert(bool condition,string message) { if(!condition) throw new Exception(message); }
    public void Smoke(string output,double scale) {
        Directory.CreateDirectory(output); Shown+=delegate {
            int phase=0,ticks=0; var timer=new Timer {Interval=350}; timer.Tick+=delegate {
                try {
                    Assert(++ticks<=85,"Worker timeout");
                    if(phase==1) {
                        if(busy) return; timer.Stop(); Assert(scan!=null&&scan.Files.Count==1&&clean.Enabled&&analyze.Enabled,"Async analysis failed"); Assert(state.Text.StartsWith("Scan complete")&&log.Text.Contains("Scanning: "),"English status/log not localized"); CapturePreview(output,"en-analysis");
                        foreach(bool en in new[]{true,false}) {
                            SetLanguage(en); bool modalSeen=false; var modalTimer=new Timer {Interval=150}; modalTimer.Tick+=delegate { var modal=Application.OpenForms.Cast<Form>().FirstOrDefault(f=>f!=this); if(modal==null) return; modalSeen=true; using(var bitmap=new Bitmap(modal.Width,modal.Height)) { modal.DrawToBitmap(bitmap,new Rectangle(0,0,modal.Width,modal.Height)); bitmap.Save(Path.Combine(output,(I18n.English?"en":"pl")+"-confirmation.png")); } modal.DialogResult=DialogResult.Cancel; modal.Close(); modalTimer.Stop(); }; modalTimer.Start(); bool confirmed=ConfirmCleaning(); modalTimer.Dispose(); Assert(modalSeen&&!confirmed&&File.Exists(scan.Files[0].Path),"Confirmation cancellation failed");
                        }
                        Assert(scan!=null&&clean.Enabled&&state.Text.StartsWith("Analiza zakończona"),"Language switch lost scan result"); recommended.PerformClick(); Assert(scan==null&&!clean.Enabled,"Scan invalidation failed");
                        File.WriteAllText(Path.Combine(output,"smoke.txt"),"PASS: Polish/English in every category; global select/deselect; manual selection caption; recommendations; administrator gating; elevation command (not executed); custom category/log scrolling; asynchronous English analysis; language switch preserves scan; selection invalidates scan; scale="+scale); timer.Stop(); timer.Dispose(); Close(); return;
                    }
                    Assert(categories.Content.Controls.Cast<Control>().Where(c=>c.Visible).All(c=>((Category)c.Tag).Group=="System"),"Startup showed overlapping categories");
                    if(scale!=1) Scale(new SizeF((float)scale,(float)scale)); ShowGroup("System");
                    foreach(bool en in new[]{false,true}) { SetLanguage(en); foreach(string group in new[]{"System","Aplikacje","Programowanie","Przeglądarki"}) { ShowGroup(group); CapturePreview(output,(en?"en-":"pl-")+group); }
                        recommended.PerformClick(); select.PerformClick(); Assert(choices.Keys.Where(c=>!choices[c].Admin||Engine.Admin).All(c=>c.Checked),"Select all did not include hidden groups"); Assert(select.Text==L("Odznacz wszystkie kategorie","Deselect all categories"),"Deselect caption wrong");
                        var one=choices.Keys.First(); one.Checked=false; Assert(select.Text==L("Zaznacz wszystkie kategorie","Select all categories"),"Manual deselection caption wrong"); one.Checked=true; select.PerformClick(); Assert(choices.Keys.All(c=>!c.Checked),"Global deselect failed");
                        Assert(choices.Keys.Where(c=>choices[c].Admin).All(c=>c.Enabled==Engine.Admin),"Administrator gating wrong");
                    }
                    var info=ElevationInfo(@"C:\Tools\clean app.exe","",true); Assert(info.Verb=="runas"&&info.UseShellExecute&&info.Arguments=="-Language en","EXE elevation command wrong"); info=ElevationInfo("powershell.exe",@"C:\Tools\clean app.ps1",false); Assert(info.Arguments.Contains(@"C:\Tools\clean app.ps1")&&info.Arguments.EndsWith("-Language pl"),"Script elevation command wrong");
                    recommended.PerformClick(); if(scale==1) ClientSize=new Size(1104,741); ShowGroup("Przeglądarki"); CapturePreview(output,"en-minimum"); categories.Bar.Value=categories.Bar.Maximum; Assert(categories.Content.Top==-categories.Bar.Value,"Category scrolling failed"); CapturePreview(output,"en-scrolled");
                    var bar=categories.Bar; var flags=System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic;
                    bar.GetType().GetMethod("OnKeyDown",flags).Invoke(bar,new object[]{new KeyEventArgs(Keys.Home)}); Assert(bar.Value==0,"Scroll Home key failed");
                    bar.GetType().GetMethod("OnKeyDown",flags).Invoke(bar,new object[]{new KeyEventArgs(Keys.End)}); Assert(bar.Value==bar.Maximum,"Scroll End key failed");
                    bar.GetType().GetMethod("OnMouseWheel",flags).Invoke(bar,new object[]{new MouseEventArgs(MouseButtons.None,0,0,0,120)}); Assert(bar.Value<bar.Maximum,"Scroll wheel failed");
                    for(int i=0;i<35;i++) Append("Scroll test "+i); log.Bar.Value=0; Assert(log.Bar.Maximum>0&&log.Bar.Value==0,"Log scrollbar range failed"); CapturePreview(output,"en-log-scroll");
                    ShowGroup("System"); string fixture=Path.Combine(output,"analysis-fixture"); Directory.CreateDirectory(fixture); string file=Path.Combine(fixture,"sample.tmp"); File.WriteAllText(file,"smoke test"); File.SetLastWriteTimeUtc(file,DateTime.UtcNow.AddDays(-3)); phase=1; Start(false,new[]{new Category("test","Test scan","",true,false,1,fixture)});
                } catch(Exception e) { File.WriteAllText(Path.Combine(output,"smoke.txt"),"FAIL: "+e); timer.Stop(); timer.Dispose(); if(worker!=null&&worker.IsBusy) worker.CancelAsync(); else Close(); }
            }; timer.Start();
        };
    }
}

public static class Tests {
    static void Check(bool ok,string name,List<string> results) { if(!ok) throw new Exception("FAIL: "+name); results.Add("PASS: "+name); }
    public static string Run(string output) {
        Directory.CreateDirectory(output); string fixture=Path.Combine(output,"fixture-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(fixture);
        string cache=Path.Combine(fixture,"Cache"),outside=Path.Combine(fixture,"Cache-other"); Directory.CreateDirectory(cache); Directory.CreateDirectory(outside);
        var results=new List<string>(); Action<string> log=s=>{}; var category=new Category("test","fixture","",true,false,1,cache);
        string old=Path.Combine(cache,"old[1].tmp"),recent=Path.Combine(cache,"new.tmp"),changed=Path.Combine(cache,"changed.tmp"),locked=Path.Combine(cache,"locked.tmp"),keep=Path.Combine(outside,"Login Data");
        foreach(string f in new[]{old,changed,locked,keep}) { File.WriteAllText(f,"fixture"); File.SetLastWriteTimeUtc(f,DateTime.UtcNow.AddDays(-3)); } File.WriteAllText(recent,"recent");
        Check(!Engine.SafeRoot(Path.GetPathRoot(fixture)),"drive root rejected",results); Check(!Engine.Inside(keep,cache),"sibling prefix rejected",results);
        var scan=Engine.Scan(new[]{category,category},()=>false,log); Check(scan.Files.Count==3 && scan.Bytes==21,"age filter and duplicate roots",results);
        var cancelled=Engine.Clean(scan,()=>true,log,p=>{}); Check(cancelled.Cancelled && File.Exists(old),"cancel before deletion",results); Check(Engine.Scan(new[]{category},()=>true,log).Cancelled,"cancel analysis",results);
        File.AppendAllText(changed,"modified after scan");
        using(var stream=new FileStream(locked,FileMode.Open,FileAccess.ReadWrite,FileShare.None)) { var cleaned=Engine.Clean(scan,()=>false,log,p=>{}); Check(cleaned.Deleted==1 && cleaned.Skipped==2 && cleaned.Bytes==7,"locked/modified files skipped; actual byte count",results); }
        Check(!File.Exists(old) && File.Exists(recent) && File.Exists(changed) && File.Exists(keep) && Directory.Exists(cache),"only scanned cache file removed; profile and directories preserved",results);
        var malicious=new Result(); malicious.Files.Add(new Candidate {Path=keep,Root=cache,Length=7,Modified=File.GetLastWriteTimeUtc(keep)}); Check(Engine.Clean(malicious,()=>false,log,p=>{}).Skipped==1 && File.Exists(keep),"out-of-scope candidate rejected",results);
        string report=String.Join(Environment.NewLine,results); File.WriteAllText(Path.Combine(output,"selftest.txt"),report); return report;
    }
}
public static class App {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    public static string EntryScript;
    public static void Run(bool smoke,string output,double scale,string language,string scriptPath) { EntryScript=scriptPath; I18n.English=language=="en"; SetProcessDPIAware(); Application.EnableVisualStyles(); using(var window=new MainWindow()) { if(smoke) window.Smoke(output,scale); Application.Run(window); } }
}
}
'@
try {
    if (-not ('CleanMax.App' -as [type])) { Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Core }
    if ($SelfTest -or $SmokeTest) {
        if ([string]::IsNullOrWhiteSpace($TestOutput)) { throw 'Podaj -TestOutput ze ścieżką katalogu testowego.' }
        if ($SelfTest) { [CleanMax.Tests]::Run($TestOutput) | Out-Null; exit 0 }
    }
    $entryScript = if ($PSCommandPath -and [IO.Path]::GetExtension($PSCommandPath) -eq '.ps1') { $PSCommandPath } else { '' }
    [CleanMax.App]::Run([bool]$SmokeTest,$TestOutput,$TestScale,$Language,$entryScript)
} catch {
    if (($SelfTest -or $SmokeTest) -and $TestOutput) { [System.IO.Directory]::CreateDirectory($TestOutput) | Out-Null; [System.IO.File]::WriteAllText((Join-Path $TestOutput 'error.txt'),($_ | Out-String)) }
    else { $errorTitle = if ($Language -eq 'en') { 'Clean Ultimate MAX PRO++ — error' } else { 'Clean Ultimate MAX PRO++ — błąd' }; [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,$errorTitle,'OK','Error') | Out-Null }
    exit 1
}
