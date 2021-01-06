module PoolingMethods
    def random(size:, items:)
      items.shuffle.each_slice(size).to_a
    end

    def numerical(size:, items:)
      items.sort{ |item| item.id}.reverse.each_slice(size).to_a
    end
end