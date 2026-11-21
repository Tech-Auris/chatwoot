# Decoration packs of the Clínica virtual. The seasonal ones come back every
# year for a while (Halloween from 16/10, Christmas from 15/11): in season,
# the pack's art (its folder) is in the clinic editor and on the map, its
# avatar accessory in the avatar editor, and Helena tells the clinic it
# arrived. `always` packs (party) are there all year, with no notice.
class VirtualClinic::Season
  ALL = [
    { key: 'christmas', folder: '11_natal', from: [11, 15], to: [12, 31], accessory: 'Accessory_20_Gorro_Natal' },
    { key: 'halloween', folder: '12_halloween', from: [10, 16], to: [10, 31], accessory: 'Accessory_24_Abobora' },
    { key: 'party', folder: '13_festa', always: true }
  ].freeze

  def self.active(date)
    ALL.select { |season| covers?(season, date) }
  end

  def self.covers?(season, date)
    return true if season[:always]

    (Date.new(date.year, *season[:from])..Date.new(date.year, *season[:to])).cover?(date)
  end

  def self.folders
    ALL.pluck(:folder)
  end

  def self.accessories
    ALL.pluck(:accessory).compact
  end
end
