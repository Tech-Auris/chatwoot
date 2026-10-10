# A Meta integration can now send conversions to several pixels, each with
# its own access token and status. The pixel each account already had moves
# into the new table as its first row, and every Meta dispatch so far is
# tied to it, so nothing stops firing on deploy.
class CreateMarketingPixels < ActiveRecord::Migration[7.1]
  def up
    create_table :marketing_pixels do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :marketing_integration, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.string :pixel_id, null: false
      t.text :access_token
      t.string :test_event_code
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :marketing_pixels, [:marketing_integration_id, :pixel_id], unique: true
    add_index :marketing_pixels, :account_id

    add_reference :conversion_event_dispatches, :marketing_pixel, foreign_key: { on_delete: :nullify }
    remove_index :conversion_event_dispatches, name: 'index_dispatches_on_provider_and_event_id'
    add_index :conversion_event_dispatches, 'provider, event_id, COALESCE(marketing_pixel_id, 0)',
              unique: true, name: 'index_dispatches_on_provider_event_id_and_pixel'

    move_existing_pixels
  end

  def down
    remove_index :conversion_event_dispatches, name: 'index_dispatches_on_provider_event_id_and_pixel'
    remove_reference :conversion_event_dispatches, :marketing_pixel, foreign_key: true
    add_index :conversion_event_dispatches, [:provider, :event_id], unique: true, name: 'index_dispatches_on_provider_and_event_id'
    drop_table :marketing_pixels
  end

  private

  # Credentials are read through the app model so encrypted rows decrypt; the
  # pixel keys then leave the integration, which keeps the ads read token
  # and the ad accounts.
  def move_existing_pixels
    MarketingIntegration.reset_column_information
    MarketingPixel.reset_column_information
    MarketingIntegration.where(provider: :meta_capi).find_each do |integration|
      credentials = integration.credentials
      next if credentials['pixel_id'].blank?

      pixel = MarketingPixel.create!(
        account_id: integration.account_id, marketing_integration_id: integration.id, name: 'Pixel principal',
        pixel_id: credentials['pixel_id'].to_s.strip, access_token: credentials['access_token'],
        test_event_code: credentials['test_event_code'].presence, status: integration.status_before_type_cast
      )
      execute("UPDATE conversion_event_dispatches SET marketing_pixel_id = #{pixel.id} " \
              "WHERE account_id = #{integration.account_id} AND provider = 0")
      # The integration now only gates the ad accounts sync; each pixel has
      # its own status.
      integration.credentials = credentials.except('pixel_id', 'access_token', 'test_event_code')
      integration.status = :active
      integration.save!(validate: false)
    end
  end
end
