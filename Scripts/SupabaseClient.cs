using System.Threading.Tasks;
using Godot;
using Newtonsoft.Json;
using Supabase;
using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;
using SupabaseClientType = Supabase.Client;

/// <summary>
/// Supabase 全局客户端（Autoload 单例）。
/// 配置读取优先级：环境变量 SUPABASE_URL / SUPABASE_ANON_KEY > res://Config/supabase.json
/// </summary>
public partial class SupabaseClient : Node
{
	private const string ConfigPath = "res://Config/supabase.json";

	/// <summary>已初始化完成的 Supabase 客户端，初始化前为 null。</summary>
	public SupabaseClientType? Instance { get; private set; }

	/// <summary>是否已初始化成功。</summary>
	public bool IsReady { get; private set; }

	/// <summary>初始化失败原因；未失败时为 null。</summary>
	public string? FailureReason { get; private set; }

	/// <summary>初始化完成信号。</summary>
	[Signal]
	public delegate void InitializedEventHandler();

	/// <summary>初始化失败信号，携带错误信息。</summary>
	[Signal]
	public delegate void InitializeFailedEventHandler(string message);

	public override void _Ready()
	{
		_ = InitializeAsync();
	}

	private async Task InitializeAsync()
	{
		var (url, anonKey) = LoadConfig();
		if (string.IsNullOrEmpty(url) || string.IsNullOrEmpty(anonKey))
		{
			FailureReason = "缺少 Supabase 配置：请设置环境变量 SUPABASE_URL/SUPABASE_ANON_KEY，或创建 Config/supabase.json（参考 supabase.json.example）";
			GD.PrintErr($"[Supabase] {FailureReason}");
			EmitSignal(SignalName.InitializeFailed, FailureReason);
			return;
		}

		try
		{
			var options = new SupabaseOptions
			{
				AutoRefreshToken = true,
				AutoConnectRealtime = true,
			};

			Instance = new SupabaseClientType(url, anonKey, options);
			await Instance.InitializeAsync();

			// 会话持久化：登录状态保存到 user://supabase-session.json
			Instance.Auth.SetPersistence(new FileSessionPersistence());
			Instance.Auth.LoadSession();

			GD.Print($"[Supabase] 客户端初始化完成：{url}");
			IsReady = true;
			EmitSignal(SignalName.Initialized);
		}
		catch (System.Exception ex)
		{
			FailureReason = ex.Message;
			GD.PrintErr($"[Supabase] 初始化失败：{ex.Message}");
			EmitSignal(SignalName.InitializeFailed, ex.Message);
		}
	}

	/// <summary>当前登录会话；未登录返回 null。</summary>
	public Session? CurrentSession => Instance?.Auth?.CurrentSession;

	/// <summary>当前登录用户；未登录返回 null。</summary>
	public User? CurrentUser => Instance?.Auth?.CurrentUser;

	private static (string url, string anonKey) LoadConfig()
	{
		// 1. 环境变量优先
		var url = OS.GetEnvironment("SUPABASE_URL");
		var anonKey = OS.GetEnvironment("SUPABASE_ANON_KEY");
		if (!string.IsNullOrEmpty(url) && !string.IsNullOrEmpty(anonKey))
		{
			return (url, anonKey);
		}

		// 2. 本地配置文件
		if (FileAccess.FileExists(ConfigPath))
		{
			using var file = FileAccess.Open(ConfigPath, FileAccess.ModeFlags.Read);
			if (file != null)
			{
				using var json = new Json();
				if (json.Parse(file.GetAsText()) == Error.Ok &&
					json.Data.VariantType == Variant.Type.Dictionary)
				{
					var dict = json.Data.AsGodotDictionary();
					if (dict.ContainsKey("url"))
					{
						url = dict["url"].AsString();
					}
					if (dict.ContainsKey("anonKey"))
					{
						anonKey = dict["anonKey"].AsString();
					}
				}
			}
		}

		return (url ?? string.Empty, anonKey ?? string.Empty);
	}
}

/// <summary>
/// 基于文件的会话持久化，将登录会话保存到 user://supabase-session.json。
/// </summary>
public class FileSessionPersistence : IGotrueSessionPersistence<Session>
{
	private const string SessionPath = "user://supabase-session.json";

	public Session? LoadSession()
	{
		if (!FileAccess.FileExists(SessionPath))
		{
			return null;
		}
		try
		{
			using var file = FileAccess.Open(SessionPath, FileAccess.ModeFlags.Read);
			return file != null ? JsonConvert.DeserializeObject<Session>(file.GetAsText()) : null;
		}
		catch (System.Exception)
		{
			return null;
		}
	}

	public void SaveSession(Session session)
	{
		using var file = FileAccess.Open(SessionPath, FileAccess.ModeFlags.Write);
		file?.StoreString(JsonConvert.SerializeObject(session));
	}

	public void DestroySession()
	{
		if (FileAccess.FileExists(SessionPath))
		{
			_ = DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(SessionPath));
		}
	}
}
