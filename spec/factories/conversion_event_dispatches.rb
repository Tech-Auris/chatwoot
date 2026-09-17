# frozen_string_literal: true

FactoryBot.define do
  factory :conversion_event_dispatch do
    account
    conversion_event { association :conversion_event, account: account }
    conversation { association :conversation, account: account }
    provider { :meta_capi }
    status { :pending }
    event_id do
      ConversionEventDispatch.build_event_id(
        conversion_event_id: conversion_event.id,
        conversation_id: conversation.id,
        provider: provider
      )
    end
    payload { {} }
    response { {} }
    attempts { 0 }
  end
end
