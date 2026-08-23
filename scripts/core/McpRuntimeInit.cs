using com.IvanMurzak.Godot.MCP.Runtime;
using Godot;

public partial class McpRuntimeInit : Node
{
    public override void _Ready()
    {
        GodotMcpRuntime.Initialize(b =>
        {
            b.WithRuntimeErrorCapture();
        }).Build();
    }
}
