using Godot;

/// <summary>
/// 游戏主场景入口。
/// </summary>
public partial class Main : Node
{
	public override void _Ready()
	{
		var supabase = GetNode<SupabaseClient>("/root/SupabaseClient");
		supabase.Initialized += OnSupabaseInitialized;
		supabase.InitializeFailed += OnSupabaseFailed;

		// Autoload 早于 Main 就绪，信号可能已发出，先查当前状态
		if (supabase.IsReady)
		{
			OnSupabaseInitialized();
		}
		else if (supabase.FailureReason != null)
		{
			OnSupabaseFailed(supabase.FailureReason);
		}
	}

	private void OnSupabaseInitialized()
	{
		GD.Print("[Main] Supabase 就绪，可以开始业务逻辑");
	}

	private void OnSupabaseFailed(string message)
	{
		GD.PrintErr($"[Main] Supabase 不可用：{message}");
	}
}
