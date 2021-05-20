needs 'Covid Surveillance/PoolingDefinitions'
needs 'Covid Surveillance/PoolingMethods'

module PoolingHelper
  include PoolingDefinitions
  include PoolingMethods
  def create_pooling_groups(items:, pooling_method:)
    pooling_details = POOLING_SCHEME[pooling_method]
    raise 'Invalid pooling method' if pooling_details.nil?

    send(pooling_details[:pooling_schema],
         size: pooling_details[:pooling_size],
         items: items)
  end

end
