# frozen_string_literal: true

module PoolingHelper
  def create_pooling_groups(items:, pool_size:, pooling_method:)
    case pooling_method
    when 'By ID'
      items.sort_by(&:id).reverse.each_slice(pool_size).to_a
    when 'By Name', 'By Batch'
      items.sort_by { |i| i.sample.name }.each_slice(pool_size).to_a
    when 'Random'
      items.shuffle.each_slice(pool_size).to_a
    else
      raise 'Invalid pooling method'
    end
  end
end
