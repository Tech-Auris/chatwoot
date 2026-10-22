# Marketing → Públicos: saved groups of contacts. Any account user builds and
# browses them; downloading and sending a campaign to one are for
# administrators and managers (AudiencePolicy), in the later endpoints.
class Api::V1::Accounts::AudiencesController < Api::V1::Accounts::BaseController
  CONTACTS_PER_PAGE = 25

  before_action :fetch_audience, except: [:index, :create, :preview, :import]
  before_action :check_authorization
  before_action :ensure_static, only: [:add_contacts, :remove_contacts]

  def index
    @audiences = Current.account.audiences.includes(:created_by).order(created_at: :desc)
    @audiences = @audiences.where(kind: params[:kind]) if Audience.kinds.key?(params[:kind])
  end

  # Opening an audience brings its size up to date.
  def show
    @audience.refresh_count!
    @events = @audience.events.includes(:user, :campaign).order(created_at: :desc).limit(50)
  end

  # A dynamic audience keeps its rule; a static one stores the given contacts,
  # or the rule's contacts right now when it comes from a filter.
  def create
    resolver = resolver_for(audience_params)
    @ignored_conditions = resolver.ignored_conditions
    @audience = Current.account.audiences.new(audience_params.merge(rule_of(resolver), created_by: Current.user))
    ActiveRecord::Base.transaction do
      @audience.save!
      @audience.static? ? @audience.add_contacts(static_contact_ids(resolver)) : @audience.refresh_count!
    end
    render :show, status: :created
  end

  def update
    resolver = resolver_for(audience_params)
    @ignored_conditions = resolver.ignored_conditions
    @audience.update!(audience_params.except(:kind, :source).merge(rule_of(resolver)))
    @audience.refresh_count!
    render :show
  end

  def destroy
    @audience.destroy!
    head :ok
  end

  # The size of a rule while it is being built, before it is saved.
  def preview
    resolver = resolver_for(audience_params)
    render json: { contacts_count: resolver.count, ignored_conditions: resolver.ignored_conditions }
  end

  def contacts
    @contacts = @audience.contacts.order(:name).page(params[:page] || 1).per(CONTACTS_PER_PAGE)
  end

  # "Congelar como público fixo": a static copy of the members right now.
  def snapshot
    @audience = @audience.freeze_as!(name: params.require(:name), user: Current.user)
    render :show, status: :created
  end

  def add_contacts
    @audience.add_contacts(Array(params[:contact_ids]))
    render :show
  end

  def remove_contacts
    @audience.remove_contacts(Array(params[:contact_ids]))
    render :show
  end

  # A spreadsheet turned into a static audience, read like a campaign's.
  def import
    result = Campaigns::AudienceCsvImportService.new(account: Current.account, file: params.require(:file)).perform
    @audience = Current.account.audiences.create!(name: params.require(:name), kind: :static, source: 'csv', created_by: Current.user)
    @audience.add_contacts(result[:contact_ids])
    @invalid_rows = result[:invalid_rows]
    render :show, status: :created
  rescue Campaigns::AudienceCsvImportService::InvalidFile => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_audience
    @audience = Current.account.audiences.find(params[:id])
  end

  def check_authorization
    authorize(@audience || Audience)
  end

  def ensure_static
    render json: { error: 'Only a static audience takes contacts by hand' }, status: :unprocessable_entity unless @audience.static?
  end

  def resolver_for(attributes)
    Audiences::Resolver.new(account: Current.account, rule: attributes[:rule], exclusion: attributes[:exclusion],
                            window: attributes[:window] || { 'type' => 'all' })
  end

  # Saved without the conditions an audience does not accept, so it never
  # keeps a condition that would not apply. Only what the request sends is
  # replaced: renaming an audience keeps its rule.
  def rule_of(resolver)
    { rule: resolver.rule, exclusion: resolver.exclusion }.slice(*audience_params.keys.map(&:to_sym))
  end

  def static_contact_ids(resolver)
    params[:contact_ids].present? ? Array(params[:contact_ids]) : resolver.contacts.pluck(:id)
  end

  CONDITION_KEYS = [:attribute_key, :filter_operator, :query_operator, :attribute_model, :custom_attribute_type, { values: [] }].freeze

  def audience_params
    params.permit(:name, :kind, :source, rule: CONDITION_KEYS, exclusion: CONDITION_KEYS, window: [:type, :days, :from, :to])
          .to_h.with_indifferent_access
  end
end
