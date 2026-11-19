# Caps the MCP tool calls of one answer, shared by all the tools of the chat.
class VirtualClinic::ToolBudget
  def initialize(limit)
    @left = limit
  end

  def spend
    (@left -= 1) >= 0
  end
end
