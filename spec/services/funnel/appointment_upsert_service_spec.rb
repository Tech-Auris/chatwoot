require 'rails_helper'

RSpec.describe Funnel::AppointmentUpsertService do
  let(:account_erp) { create(:erp_source) }
  let(:other_erp) { create(:erp_source) }
  let(:account) { create(:account, erp_source: account_erp) }
  let(:conversation) { create(:conversation, account: account) }

  let(:booking) do
    {
      source_id: other_erp.id, external_id: 'ag_789', scheduled_for: '2026-11-12T14:30:00-03:00',
      professional: { id: 'prof_12', name: 'Dra. Ana' }, procedure: { id: 'proc_3', name: 'Avaliação' }
    }
  end

  def record(payload, **)
    described_class.new(conversation: conversation, payload: payload, **).perform
  end

  it 'records a booking with its origin, date, professional and procedure' do
    appointment = record(booking, stage_name: 'Agendado')

    expect(appointment).to have_attributes(
      erp_source: other_erp, external_id: 'ag_789', status: 'scheduled', contact_id: conversation.contact_id,
      professional_external_id: 'prof_12', professional_name: 'Dra. Ana', procedure_name: 'Avaliação'
    )
    expect(appointment.scheduled_for).to eq(Time.zone.parse('2026-11-12T17:30:00Z'))
  end

  it 'uses the account ERP when no source_id comes' do
    expect(record(booking.except(:source_id)).erp_source).to eq(account_erp)
  end

  it 'updates the same appointment when the call is resent or rescheduled' do
    record(booking, stage_name: 'Agendado')
    record(booking.merge(scheduled_for: '2026-11-14T10:00:00-03:00'))

    expect(account.appointments.count).to eq(1)
    expect(account.appointments.first).to have_attributes(status: 'rescheduled', professional_name: 'Dra. Ana')
  end

  it 'keeps keys left out and clears keys sent as null' do
    record(booking)
    appointment = record({ source_id: other_erp.id, external_id: 'ag_789', professional: nil })

    expect(appointment).to have_attributes(professional_name: nil, procedure_name: 'Avaliação')
    expect(appointment.scheduled_for).to be_present
  end

  it 'holds several open appointments and asks for external_id when it cannot tell them apart' do
    record(booking)
    record(booking.merge(external_id: 'ag_790'))

    expect(conversation.appointments.open.count).to eq(2)
    expect { record({ scheduled_for: '2026-11-20T09:00:00-03:00' }) }
      .to raise_error(ArgumentError, I18n.t('funnel.appointments.external_id_required'))
  end

  it 'updates the only open appointment when external_id is missing' do
    record(booking.except(:external_id))
    record({ procedure: { id: 'proc_9', name: 'Retorno' } })

    expect(conversation.appointments.sole.procedure_name).to eq('Retorno')
  end

  it 'records the attendance with each procedure closed, without adding up on resend' do
    record(booking)
    attendance = {
      source_id: other_erp.id, external_id: 'ag_789', attended_at: '2026-11-12T15:10:00-03:00',
      procedures: [{ id: 'proc_3', name: 'Protocolo Goldincision', amount_paid: 4500.0 }, { id: 'proc_8', name: 'Retorno', amount_paid: 0 }]
    }

    2.times { record(attendance, attendance: true) }

    appointment = conversation.appointments.sole
    expect(appointment.status).to eq('attended')
    expect(appointment.procedures.pluck(:procedure_name, :amount_paid_cents))
      .to contain_exactly(['Protocolo Goldincision', 450_000], ['Retorno', 0])
  end

  it 'takes the status of the no-show and lost stages' do
    record(booking)

    expect(record({ source_id: other_erp.id, external_id: 'ag_789' }, stage_name: 'No-Show').status).to eq('no_show')
  end

  it 'refuses an unknown source_id' do
    expect { record(booking.merge(source_id: 999_999)) }.to raise_error(ArgumentError, /999999/)
  end
end
