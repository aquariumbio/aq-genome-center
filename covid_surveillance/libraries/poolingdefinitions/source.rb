module PoolingDefinitions
  POOLING_SCHEME = {
    'Standard' => {
      pooling_size: 10,
      pooling_schema: 'numerical'
    },
    'Random' => {
      pooling_size: 10,
      pooling_schema: 'random'
    }
  }
end