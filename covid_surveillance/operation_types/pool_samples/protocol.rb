# frozen_string_literal: true

needs 'Covid Surveillance/PoolSamplesHelper'

class Protocol
  include PoolSamplesHelper

  ########## DEFAULT PARAMS ##########

  # Default parameters that are applied equally to all operations.
  #   Can be overridden by:
  #   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
  #   * Adding a JSON-formatted list of key, value pairs to an `Operation`
  #     input of type JSON and named `Options`.
  #
  def default_job_params
    {
      max_specimens_per_operation: 96,
      pool_size: 10,
      pooling_method: 'By Batch',
      sample_rack: { dimensions: [1, 10], name: 'Specimen Rack' },
      transfer_volume: { qty: 5, units: MICROLITERS },
      plate_location: 'M20'
    }
  end

  # Default parameters that are applied to individual operations.
  #   Can be overridden by:
  #   * Adding a JSON-formatted list of key, value pairs to an `Operation`
  #     input of type JSON and named `Options`.
  #
  def default_operation_params
    {}
  end

  ########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    validate(
      operations: operations,
      max_specimens: @job_params[:max_specimens_per_operation]
    )
    return {} if operations.errored.any?

    ops_by_plate = operations.group_by { |op| op.output(POOLED_PLATE).sample }

    ops_by_plate.each do |sample, ops|
      ops.retrieve

      pooling_groups = create_pooling_groups(
        items: collect_specimens(operations: ops),
        pool_size: @job_params[:pool_size],
        pooling_method: @job_params[:pooling_method]
      )

      microtiter_plate = add_pools(
        collection: create_output_collection(sample: sample, operations: ops),
        pooling_groups: pooling_groups
      )

      inspect_first_three(microtiter_plate.collection) if debug

      # ops.each do |op|
      #   pool_manually(operation: op,
      #                 pooling_groups: pooling_groups,
      #                 opts: @job_params)
      # end

      store_items([microtiter_plate.collection],
                  location: @job_params[:plate_location])
    end

    {}
  end
end
