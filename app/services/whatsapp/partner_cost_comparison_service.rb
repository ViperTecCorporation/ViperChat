class Whatsapp::PartnerCostComparisonService
  def initialize(timezone:, rates:, ad_window_days:)
    @options = { timezone: timezone, rates: rates, ad_window_days: ad_window_days }
  end

  def perform(rows:, since:, until_time:)
    period = { since: since, until_time: until_time }
    actual = Whatsapp::PartnerCostSimulationService.new(**@options).perform(rows: rows, **period)
    all_meta = rows.map { |row| row[:provider] == 'unoapi' ? row.merge(provider: 'whatsapp_cloud') : row }
    hypothetical = Whatsapp::PartnerCostSimulationService.new(**@options).perform(rows: all_meta, **period)
    actual_cost = BigDecimal(actual[:estimated_cost])
    all_meta_cost = BigDecimal(hypothetical[:estimated_cost])
    actual.merge(comparison: {
                   all_meta_cost: hypothetical[:estimated_cost], avoided_meta_cost: (all_meta_cost - actual_cost).to_s('F'),
                   avoided_percent: all_meta_cost.positive? ? ((all_meta_cost - actual_cost) / all_meta_cost * 100).round(2).to_s('F') : nil,
                   unclassified: hypothetical[:unclassified], unpriced: hypothetical[:unpriced]
                 })
  end
end
