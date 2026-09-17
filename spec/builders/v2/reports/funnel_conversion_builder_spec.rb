require 'rails_helper'

RSpec.describe V2::Reports::FunnelConversionBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:stages) do
    {
      lead: create(:funnel_stage, name: "lead_#{SecureRandom.hex(4)}", position: 0, closed: false),
      qualified: create(:funnel_stage, name: "qualified_#{SecureRandom.hex(4)}", position: 1, closed: false),
      won: create(:funnel_stage, name: "won_#{SecureRandom.hex(4)}", position: 99, closed: true),
      lost: create(:funnel_stage, name: "lost_#{SecureRandom.hex(4)}", position: 100, closed: true)
    }
  end
  let(:params) do
    { since: 7.days.ago.to_time.to_i.to_s, until: Time.zone.now.end_of_day.to_time.to_i.to_s }
  end
  let(:builder) { described_class.new(account: account, params: params) }

  def conversation_with_id
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end

  def stage_change(conv_id:, new_stage:, created_at: 1.day.ago, previous_stage: nil, loss_reason: nil)
    create(:funnel_stage_change,
           account: account, conversation_id: conv_id,
           contact: contact, inbox: inbox,
           previous_stage: previous_stage, new_stage: new_stage,
           loss_reason: loss_reason, created_at: created_at)
  end

  before { stages }

  describe '#build' do
    context 'when there are no active stages' do
      before { FunnelStage.update_all(active: false) } # rubocop:disable Rails/SkipsModelValidations

      it 'returns empty stages, zeroed KPIs, and empty loss_reasons' do
        result = described_class.new(account: create(:account), params: params).build
        expect(result[:stages]).to eq([])
        expect(result[:kpis]).to eq(
          total_leads: 0,
          scheduling_count: 0, scheduling_rate: nil,
          confirmation_count: 0, confirmation_rate: nil,
          attendance_count: 0, attendance_rate: nil,
          no_show_count: 0, no_show_rate: nil
        )
        expect(result[:loss_reasons]).to eq([])
      end
    end

    context 'when no transitions happened in the period' do
      it 'returns one row per stage with zeroed count and nil conversion/drop-off on last' do
        result = builder.build

        lead_row = result[:stages].find { |row| row[:name] == stages[:lead].name }
        last_row = result[:stages].last
        expect(lead_row[:count]).to eq(0)
        expect(last_row[:conversion_rate]).to be_nil
        expect(last_row[:drop_off_count]).to be_nil
      end
    end

    context 'with distinct counting and conversion math' do
      before do
        # 3 distinct conversations entered "lead", one of them re-entered → still 3 distinct.
        3.times do
          conv = conversation_with_id
          stage_change(conv_id: conv.id, new_stage: stages[:lead].name)
        end
        # First conv re-entered "lead" — should NOT double count.
        first_conv = account.conversations.first
        stage_change(conv_id: first_conv.id, new_stage: stages[:lead].name, created_at: 12.hours.ago)

        # 2 of those 3 moved to qualified.
        account.conversations.limit(2).each do |conv|
          stage_change(conv_id: conv.id, previous_stage: stages[:lead].name, new_stage: stages[:qualified].name)
        end

        # 1 won, 1 lost (with loss reason).
        loss = create(:loss_reason, name: "reason_#{SecureRandom.hex(4)}")
        first_qualified = account.conversations.first
        second_qualified = account.conversations.offset(1).first
        stage_change(conv_id: first_qualified.id, previous_stage: stages[:qualified].name, new_stage: stages[:won].name)
        stage_change(conv_id: second_qualified.id, previous_stage: stages[:qualified].name,
                     new_stage: stages[:lost].name, loss_reason: loss)
      end

      it 'counts distinct conversations per stage' do
        result = builder.build
        expect(result[:stages].find { |row| row[:name] == stages[:lead].name }[:count]).to eq(3)
        expect(result[:stages].find { |row| row[:name] == stages[:qualified].name }[:count]).to eq(2)
        expect(result[:stages].find { |row| row[:name] == stages[:won].name }[:count]).to eq(1)
        expect(result[:stages].find { |row| row[:name] == stages[:lost].name }[:count]).to eq(1)
      end

      it 'computes conversion_rate as next/current and drop_off as difference' do
        result = builder.build
        lead_row = result[:stages].find { |row| row[:name] == stages[:lead].name }
        # 2 of 3 progressed from lead to qualified → 66.67% / drop-off 1.
        expect(lead_row[:conversion_rate]).to be_within(0.01).of(66.67)
        expect(lead_row[:drop_off_count]).to eq(1)
      end

      # rubocop:disable RSpec/MultipleExpectations
      it 'reports KPIs: total_leads + scheduling/confirmation/attendance/no_show rates' do
        # Point the KPI canon at the spec's random-named test stages so we can
        # exercise the math without relying on the seeder's canonical names.
        # confirmation has no matching stage in this setup — it should land
        # as zero count / nil rate so the data shape stays defined.
        stub_const('V2::Reports::FunnelConversionBuilder::CONFIRMATION_STAGE_NAME', '__no_matching_stage__')
        stub_const('V2::Reports::FunnelConversionBuilder::ATTENDANCE_STAGE_NAME', stages[:won].name)
        stub_const('V2::Reports::FunnelConversionBuilder::NO_SHOW_STAGE_NAME', stages[:lost].name)
        stages[:qualified].update!(
          chart_group: V2::Reports::FunnelConversionBuilder::SCHEDULING_CHART_GROUP
        )

        kpis = builder.build[:kpis]
        # 3 entered lead (the first open stage = total_leads denominator).
        # 2 entered qualified → scheduling = 2 → 66.67%.
        # 0 entered confirmation (no matching stage) → 0 / 0%.
        # 1 entered won → attendance = 1 → 33.33%.
        # 1 entered lost (stubbed as no-show) → no_show = 1 → 33.33%.
        expect(kpis[:total_leads]).to eq(3)
        expect(kpis[:scheduling_count]).to eq(2)
        expect(kpis[:scheduling_rate]).to be_within(0.01).of(66.67)
        expect(kpis[:confirmation_count]).to eq(0)
        expect(kpis[:confirmation_rate]).to eq(0.0)
        expect(kpis[:attendance_count]).to eq(1)
        expect(kpis[:attendance_rate]).to be_within(0.01).of(33.33)
        expect(kpis[:no_show_count]).to eq(1)
        expect(kpis[:no_show_rate]).to be_within(0.01).of(33.33)
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context 'when a downstream stage has entries the first stage does not (jumps / earlier-period entrants)' do
      # Real prod incident: operators reported "Em Qualificação = 30" being
      # bigger than "Total de leads = 21" and reading it (correctly) as a
      # broken funnel. Root cause was the first bar counting entries into
      # the first stage ONLY within the period; conversations that entered
      # the first stage BEFORE the period and moved to a later stage IN
      # the period showed up downstream but not on the first bar. The
      # first bar now shows the universe of conversations touched by the
      # funnel in the period, so it always caps the downstream bars.
      before do
        # 1 conv entered "lead" in-period.
        first = conversation_with_id
        stage_change(conv_id: first.id, new_stage: stages[:lead].name)

        # 2 distinct convs entered "qualified" without touching "lead" in
        # the period (e.g. they entered "lead" before the period, or the
        # workflow moved them straight into qualified).
        2.times do
          conv = conversation_with_id
          stage_change(conv_id: conv.id, new_stage: stages[:qualified].name)
        end
      end

      it 'anchors the first bar to the universe of stage changes so it always caps the downstream bars' do
        result = builder.build
        lead_row = result[:stages].find { |row| row[:name] == stages[:lead].name }
        qualified_row = result[:stages].find { |row| row[:name] == stages[:qualified].name }

        # 3 distinct convs touched the funnel in the period → the first bar
        # rolls all of them up, not just the one that entered "lead".
        expect(lead_row[:count]).to eq(3)
        expect(qualified_row[:count]).to eq(2)
        expect(lead_row[:conversion_rate]).to be_within(0.01).of(66.67)
        expect(lead_row[:conversion_exceeds_previous]).to be false
        expect(lead_row[:drop_off_count]).to eq(1)
      end

      it 'uses the same universe as the KPI total_leads denominator' do
        kpis = builder.build[:kpis]
        expect(kpis[:total_leads]).to eq(3)
      end
    end

    context 'with chart_display_name set on a stage' do
      before do
        stages[:lead].update!(chart_display_name: 'Total de leads')
        conv = conversation_with_id
        stage_change(conv_id: conv.id, new_stage: stages[:lead].name)
      end

      it 'renders the display name instead of the canonical stage name' do
        result = builder.build
        expect(result[:stages].map { |row| row[:name] }).to include('Total de leads')
        expect(result[:stages].map { |row| row[:name] }).not_to include(stages[:lead].name)
      end
    end

    context 'with chart_visible: false on a stage' do
      before do
        stages[:lost].update!(chart_visible: false)
        # A loss-flagged transition still counts toward KPIs even though
        # the lost stage is hidden from the chart.
        loss = create(:loss_reason, name: "reason_#{SecureRandom.hex(4)}")
        conv = conversation_with_id
        stage_change(conv_id: conv.id, new_stage: stages[:lost].name, loss_reason: loss)
      end

      it 'omits the hidden stage from chart rows' do
        result = builder.build
        expect(result[:stages].map { |row| row[:name] }).not_to include(stages[:lost].name)
      end

      it 'still counts the hidden closed stage toward KPIs' do
        # The hidden lost stage stands in for No-Show in the canonical
        # mapping; chart_visible=false hides it from the chart but the KPI
        # math should still see the entry.
        stub_const('V2::Reports::FunnelConversionBuilder::NO_SHOW_STAGE_NAME', stages[:lost].name)
        expect(builder.build[:kpis][:no_show_count]).to eq(1)
      end
    end

    context 'with chart_group merging multiple stages' do
      let(:agendamento_a) do
        create(:funnel_stage, name: "agendamento_a_#{SecureRandom.hex(4)}", position: 5, chart_group: 'Agendamento')
      end
      let(:agendamento_b) do
        create(:funnel_stage, name: "agendamento_b_#{SecureRandom.hex(4)}", position: 6, chart_group: 'Agendamento')
      end

      before do
        agendamento_a
        agendamento_b

        # conv_a entered only the first member.
        conv_a = conversation_with_id
        stage_change(conv_id: conv_a.id, new_stage: agendamento_a.name)

        # conv_b traversed both — must count once in the merged group.
        conv_b = conversation_with_id
        stage_change(conv_id: conv_b.id, new_stage: agendamento_a.name)
        stage_change(conv_id: conv_b.id, previous_stage: agendamento_a.name, new_stage: agendamento_b.name)
      end

      it 'collapses members into a single row keyed by the chart_group' do
        report = builder.build
        merged = report[:stages].find { |row| row[:name] == 'Agendamento' }

        expect(merged).not_to be_nil
        expect(merged[:count]).to eq(2)
        expect(report[:stages].map { |row| row[:name] }).not_to include(agendamento_a.name, agendamento_b.name)
      end
    end

    context 'with loss_reasons attached to transitions' do
      let(:reason_price) { create(:loss_reason, name: "price_#{SecureRandom.hex(4)}") }
      let(:reason_no_response) { create(:loss_reason, name: "no_response_#{SecureRandom.hex(4)}") }

      before do
        # 2 distinct convs lost to "price" (one re-entered with the same reason
        # — should NOT double-count) and 1 lost to "no response".
        conv_a = conversation_with_id
        stage_change(conv_id: conv_a.id, new_stage: stages[:lost].name, loss_reason: reason_price)
        stage_change(conv_id: conv_a.id, new_stage: stages[:lost].name, loss_reason: reason_price, created_at: 12.hours.ago)
        conv_b = conversation_with_id
        stage_change(conv_id: conv_b.id, new_stage: stages[:lost].name, loss_reason: reason_price)
        conv_c = conversation_with_id
        stage_change(conv_id: conv_c.id, new_stage: stages[:lost].name, loss_reason: reason_no_response)
      end

      it 'aggregates distinct conversations per loss reason sorted desc' do
        rows = builder.build[:loss_reasons]

        expect(rows.length).to eq(2)
        expect(rows.first[:name]).to eq(reason_price.name)
        expect(rows.first[:count]).to eq(2)
        expect(rows.first[:percentage]).to be_within(0.01).of(66.67)
        expect(rows.last[:name]).to eq(reason_no_response.name)
        expect(rows.last[:count]).to eq(1)
        expect(rows.last[:percentage]).to be_within(0.01).of(33.33)
      end

      it 'omits loss reasons with no entries in the period' do
        unused = create(:loss_reason, name: "unused_#{SecureRandom.hex(4)}")
        expect(builder.build[:loss_reasons].map { |r| r[:name] }).not_to include(unused.name)
      end
    end

    context 'with inbox_id filter' do
      let(:other_inbox) { create(:inbox, account: account) }

      before do
        # Two convs in `inbox`, one in `other_inbox`. Only the matching scope
        # should show up in the counts.
        conv_a = conversation_with_id
        stage_change(conv_id: conv_a.id, new_stage: stages[:lead].name)
        conv_b = conversation_with_id
        stage_change(conv_id: conv_b.id, new_stage: stages[:lead].name)

        other_conv = create(:conversation, account: account, inbox: other_inbox, contact: contact)
        create(:funnel_stage_change,
               account: account, conversation_id: other_conv.id,
               contact: contact, inbox: other_inbox,
               previous_stage: nil, new_stage: stages[:lead].name)
      end

      it 'only counts changes from the chosen inbox' do
        filtered = described_class.new(
          account: account,
          params: params.merge(inbox_id: inbox.id)
        ).build

        lead_row = filtered[:stages].find { |row| row[:name] == stages[:lead].name }
        expect(lead_row[:count]).to eq(2)
      end
    end

    context 'with AI / manual split per stage' do
      before do
        ai_conv = conversation_with_id
        ai_conv.update!(ai_enabled: true)
        stage_change(conv_id: ai_conv.id, new_stage: stages[:lead].name)

        manual_conv = conversation_with_id
        manual_conv.update!(ai_enabled: false)
        stage_change(conv_id: manual_conv.id, new_stage: stages[:lead].name)

        another_manual = conversation_with_id
        another_manual.update!(ai_enabled: false)
        stage_change(conv_id: another_manual.id, new_stage: stages[:lead].name)
      end

      it 'returns count_ai and count_manual alongside the total per stage' do
        lead_row = builder.build[:stages].find { |row| row[:name] == stages[:lead].name }

        expect(lead_row[:count]).to eq(3)
        expect(lead_row[:count_ai]).to eq(1)
        expect(lead_row[:count_manual]).to eq(2)
      end
    end

    context 'with label filter' do
      let(:matching_label) { 'reativar-fup' }

      before do
        labeled_conv = conversation_with_id
        labeled_conv.update_labels(matching_label)
        stage_change(conv_id: labeled_conv.id, new_stage: stages[:lead].name)

        bare_conv = conversation_with_id
        stage_change(conv_id: bare_conv.id, new_stage: stages[:lead].name)
      end

      it 'only counts changes from conversations carrying the label' do
        filtered = described_class.new(
          account: account,
          params: params.merge(label: matching_label)
        ).build

        lead_row = filtered[:stages].find { |row| row[:name] == stages[:lead].name }
        expect(lead_row[:count]).to eq(1)
      end
    end

    context 'with origem filter' do
      before do
        fb_conv = create(:conversation, account: account, inbox: inbox, origem: 'Facebook')
        ig_conv = create(:conversation, account: account, inbox: inbox, origem: 'Instagram')
        bare_conv = create(:conversation, account: account, inbox: inbox)

        [fb_conv, ig_conv, bare_conv].each do |conv|
          create(:funnel_stage_change,
                 account: account, conversation_id: conv.id,
                 contact: conv.contact, inbox: inbox,
                 previous_stage: nil, new_stage: stages[:lead].name)
        end
      end

      it 'only counts stage changes for conversations whose own origem matches' do
        filtered = described_class.new(account: account, params: params.merge(origem: 'Facebook')).build
        lead_row = filtered[:stages].find { |row| row[:name] == stages[:lead].name }

        expect(lead_row[:count]).to eq(1)
      end

      # The Sem Origem token surfaces conversations that never got attributed
      # — auto or manual — which is the way operators find "leaks" in the
      # pipeline.
      it 'maps the __none__ token to conversations with no origem set' do
        filtered = described_class.new(account: account, params: params.merge(origem: '__none__')).build
        lead_row = filtered[:stages].find { |row| row[:name] == stages[:lead].name }

        expect(lead_row[:count]).to eq(1)
      end
    end

    context 'with campaign_referral attached to conversations' do
      let!(:qualifying) { create(:funnel_stage, name: 'Em Qualificação', position: 10) }
      let!(:agendado) { create(:funnel_stage, name: 'Agendado', position: 20, chart_group: 'Agendamento') }
      let!(:reagendado) { create(:funnel_stage, name: 'Reagendado', position: 21, chart_group: 'Agendamento') }
      let!(:confirmado) { create(:funnel_stage, name: 'Confirmado', position: 30) }
      let!(:comparecimento) { create(:funnel_stage, name: 'Comparecimento (ganho)', position: 40, closed: true) }

      def ad_conversation(source_id:, title: 'Anúncio', source_url: 'https://fb.me/x')
        create(
          :conversation,
          account: account,
          inbox: inbox,
          contact: contact,
          additional_attributes: {
            'campaign_referral' => {
              'source_id' => source_id,
              'title' => title,
              'source_url' => source_url
            }
          }
        )
      end

      it 'aggregates leads and stage buckets per Meta ad, sorted by leads desc' do # rubocop:disable RSpec/MultipleExpectations
        # Ad A: 2 leads (both qualify), 1 reaches "Agendado", 1 reaches "Confirmado".
        conv_a1 = ad_conversation(source_id: 'FB-1', title: 'Campanha A', source_url: 'https://fb.me/a')
        conv_a2 = ad_conversation(source_id: 'FB-1', title: 'Campanha A', source_url: 'https://fb.me/a')
        [conv_a1, conv_a2].each do |conv|
          stage_change(conv_id: conv.id, new_stage: qualifying.name)
        end
        stage_change(conv_id: conv_a1.id, previous_stage: qualifying.name, new_stage: agendado.name)
        stage_change(conv_id: conv_a1.id, previous_stage: agendado.name, new_stage: confirmado.name)

        # Ad B: 1 lead, all the way to "Comparecimento (ganho)".
        conv_b = ad_conversation(source_id: 'IG-2', title: 'Campanha B', source_url: 'https://ig.me/b')
        stage_change(conv_id: conv_b.id, new_stage: qualifying.name)
        stage_change(conv_id: conv_b.id, previous_stage: qualifying.name, new_stage: reagendado.name)
        stage_change(conv_id: conv_b.id, previous_stage: reagendado.name, new_stage: confirmado.name)
        stage_change(conv_id: conv_b.id, previous_stage: confirmado.name, new_stage: comparecimento.name)

        # No-ad conversation — must be ignored (no source_id on the referral).
        no_ad_conv = conversation_with_id
        stage_change(conv_id: no_ad_conv.id, new_stage: qualifying.name)

        result = builder.build
        rows = result[:campaign_breakdown]

        expect(rows.map { |row| row[:source_id] }).to eq(%w[FB-1 IG-2])

        ad_a = rows.find { |row| row[:source_id] == 'FB-1' }
        expect(ad_a).to include(
          title: 'Campanha A',
          source_url: 'https://fb.me/a',
          leads: 2
        )
        expect(ad_a[:qualifying]).to eq(count: 2, rate: 100.0)
        expect(ad_a[:scheduling]).to eq(count: 1, rate: 50.0)
        expect(ad_a[:confirmation]).to eq(count: 1, rate: 50.0)
        expect(ad_a[:attendance]).to eq(count: 0, rate: 0.0)

        ad_b = rows.find { |row| row[:source_id] == 'IG-2' }
        expect(ad_b[:leads]).to eq(1)
        expect(ad_b[:scheduling]).to eq(count: 1, rate: 100.0)
        expect(ad_b[:attendance]).to eq(count: 1, rate: 100.0)
      end

      it 'returns an empty campaign_breakdown when no conversations carry an ad tag' do
        conv = conversation_with_id
        stage_change(conv_id: conv.id, new_stage: qualifying.name)

        expect(builder.build[:campaign_breakdown]).to eq([])
      end

      # Fase 3 · F4: campaign_breakdown rows carry spend / CPL / CPA / ROAS
      # aggregated from campaign_spends for the same source_id in the period.
      it 'enriches each ad row with spend, CPL, CPA and ROAS' do
        account.update!(average_ticket: 500)

        conv = ad_conversation(source_id: 'FB-SPEND', title: 'Campanha $', source_url: 'https://fb.me/z')
        stage_change(conv_id: conv.id, new_stage: qualifying.name)
        stage_change(conv_id: conv.id, previous_stage: qualifying.name, new_stage: comparecimento.name)

        create(:campaign_spend, account: account, provider: :meta, source_id: 'FB-SPEND',
                                source_type: 'meta_ad', period_start: Date.current, period_end: Date.current,
                                amount_cents: 10_000, currency: 'BRL')

        row = builder.build[:campaign_breakdown].find { |r| r[:source_id] == 'FB-SPEND' }
        expect(row).to include(spend_cents: 10_000)
        expect(row[:cpl_cents]).to eq(10_000) # 10_000 cents / 1 lead
        expect(row[:cpa_cents]).to eq(10_000) # 10_000 cents / 1 attendance
        expect(row[:roas]).to eq(5.0)         # 500.00 revenue / 100.00 spend
      end

      it 'leaves derived metrics nil when there is no spend for an ad' do
        conv = ad_conversation(source_id: 'FB-NOSPEND', title: 'Órfã', source_url: 'https://fb.me/o')
        stage_change(conv_id: conv.id, new_stage: qualifying.name)

        row = builder.build[:campaign_breakdown].find { |r| r[:source_id] == 'FB-NOSPEND' }
        expect(row[:spend_cents]).to eq(0)
        expect(row[:cpl_cents]).to be_nil
        expect(row[:cpa_cents]).to be_nil
        expect(row[:roas]).to be_nil
      end
    end
  end
end
