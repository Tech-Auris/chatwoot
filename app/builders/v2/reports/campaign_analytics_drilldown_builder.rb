# The conversations behind a number of Marketing → Analytics: one ad
# (`source_id`) and one column (`metric`), counted the way the report counts
# them, so the list has exactly as many rows as the number clicked.
#
#   conversations → conversations tagged with the ad and created in the period
#   qualified / scheduled / confirmed / attendance → conversations of the ad that entered
#     that stage in the period (one row each, its latest entry)
class V2::Reports::CampaignAnalyticsDrilldownBuilder < V2::Reports::FunnelConversionDrilldownBuilder
  def build
    params[:metric] == 'conversations' ? build_conversations : super
  end

  private

  def narrow(scope)
    ad_scope(scope).where(new_stage: metric_stage_names)
  end

  def metric_stage_names
    case params[:metric]
    when 'qualified' then [QUALIFYING_STAGE_NAME]
    when 'scheduled' then scheduling_member_names(FunnelStage.active.to_a)
    when 'confirmed' then [CONFIRMATION_STAGE_NAME]
    when 'attendance' then [ATTENDANCE_STAGE_NAME]
    else raise UnknownStage
    end
  end

  def build_conversations
    scope = ad_conversations
    scope = scope.where(created_at: range) if range.present?
    page = scope.order(created_at: :desc, id: :desc).page(current_page).per(PER_PAGE).includes(:contact, :inbox, :funnel_stage)

    {
      rows: page.map { |conversation| conversation_row(conversation) },
      meta: { current_page: current_page, per_page: PER_PAGE, total_count: scope.count }
    }
  end

  def ad_conversations
    account.conversations.where("conversations.additional_attributes -> 'campaign_referral' ->> 'source_id' = ?", params[:source_id].to_s)
  end

  # No stage change behind a conversation row: when it arrived and the stage
  # it is on now.
  def conversation_row(conversation)
    {
      conversation_id: conversation.display_id,
      contact_name: conversation.contact.name,
      contact_phone: conversation.contact.phone_number,
      entered_at: conversation.created_at.iso8601,
      stage: conversation.funnel_stage&.name,
      previous_stage: nil,
      moved_by: nil,
      inbox_name: conversation.inbox.name,
      origem: conversation.origem,
      ad_title: conversation.additional_attributes&.dig('campaign_referral', 'title'),
      loss_reason: nil
    }
  end
end
