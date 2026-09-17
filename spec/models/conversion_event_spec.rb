require 'rails_helper'

RSpec.describe ConversionEvent do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:dispatches).class_name('ConversionEventDispatch').dependent(:destroy) }
  end

  describe 'validations' do
    subject { create(:conversion_event) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:account_id) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:trigger_type).with_values(funnel_stage_reached: 0, label_added: 1, automation_action: 2) }
  end

  describe 'trigger_config validation' do
    it 'requires funnel_stage_id when trigger is funnel_stage_reached' do
      event = build(:conversion_event, :funnel_stage_reached, trigger_config: {})
      expect(event).to be_invalid
      expect(event.errors[:trigger_config].first).to include('funnel_stage_id')
    end

    it 'requires label when trigger is label_added' do
      event = build(:conversion_event, :label_added, trigger_config: {})
      expect(event).to be_invalid
      expect(event.errors[:trigger_config].first).to include('label')
    end

    it 'accepts empty trigger_config for automation_action' do
      event = build(:conversion_event, trigger_type: :automation_action, trigger_config: {})
      expect(event).to be_valid
    end
  end

  describe 'provider event validation' do
    # An event configured with neither Meta nor Google would silently no-op,
    # which is the surprising kind of empty state we want to catch on save.
    it 'rejects an event with neither meta nor google event name set' do
      event = build(:conversion_event, meta_event_name: nil, google_event_name: nil)
      expect(event).to be_invalid
      expect(event.errors[:base].first).to include('meta_event_name', 'google_event_name')
    end

    it 'accepts an event with only meta_event_name' do
      event = build(:conversion_event, meta_event_name: 'Lead', google_event_name: nil)
      expect(event).to be_valid
    end

    it 'accepts an event with only google_event_name' do
      event = build(:conversion_event, meta_event_name: nil, google_event_name: 'book_appointment')
      expect(event).to be_valid
    end
  end

  describe 'trigger lookup scopes' do
    let(:account) { create(:account) }

    it 'matches funnel_stage_reached events by stage id' do
      match = create(:conversion_event, :funnel_stage_reached, account: account, trigger_config: { 'funnel_stage_id' => 7 })
      _other = create(:conversion_event, :funnel_stage_reached, account: account, trigger_config: { 'funnel_stage_id' => 8 })

      expect(account.conversion_events.for_funnel_stage(7)).to contain_exactly(match)
    end

    it 'matches label_added events by label string' do
      match = create(:conversion_event, :label_added, account: account, trigger_config: { 'label' => 'converteu' })
      _other = create(:conversion_event, :label_added, account: account, trigger_config: { 'label' => 'agendado' })

      expect(account.conversion_events.for_label('converteu')).to contain_exactly(match)
    end
  end
end
