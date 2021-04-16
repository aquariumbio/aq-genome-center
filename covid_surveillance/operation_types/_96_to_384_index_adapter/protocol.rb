# typed: false
# frozen_string_literal: true

needs 'Covid Surveillance/Transfer_96_384'

class Protocol

  include Transfer_96_384

  PLATE_A = 'Plate A'
  PLATE_B = 'Plate B'
  PLATE_C = 'Plate C'
  PLATE_D = 'Plate D'
  SAMPLE_PLATE = '384 Index Plate'

  PLATE_TRANSFER_MAP = [
    {
      plate: PLATE_A,
      rows: [0, 7],
      columns: [0, 11]
    },
    {
      plate: PLATE_B,
      rows: [8, 15],
      columns: [0, 11]
    },
    {
      plate: PLATE_C,
      rows: [0, 7],
      columns: [12, 23]
    },
    {
      plate: PLATE_D,
      rows: [8, 15],
      columns: [12, 23]
    }
  ].freeze

  ################ Composition Parts ####################

  def components
    [ 
       {
         input_name: PLATE_A,
         qty: 8.5, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         suggested_ot: PLATE96
       },
       {
        input_name: PLATE_B,
        qty: 8.5, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        suggested_ot: PLATE96
      },
      {
        input_name: PLATE_C,
        qty: 8.5, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        suggested_ot: PLATE96
      },
      {
        input_name: PLATE_D,
        qty: 8.5, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        suggested_ot: PLATE96
      },
      {
        input_name: SAMPLE_PLATE,
        qty: nil, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        suggested_ot: PLATE
      }
    ]
  end

  ########## DEFAULT PARAMS ##########

  # Default parameters that are applied equally to all operations.
  #   Can be overridden by:
  #   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
  #   * Adding a JSON-formatted list of key, value pairs to an `Operation`
  #     input of type JSON and named `Options`.
  def default_job_params
    {
    }
  end

  # Default parameters that are applied to individual operations.
  #   Can be overridden by:
  #   * Adding a JSON-formatted list of key, value pairs to an `Operation`
  #     input of type JSON and named `Options`.
  #
  def default_operation_params
    {
      tr_96_384_program: '96_to_384_index',
      tr_96_384_robot: Biomek::MODEL
    }
  end

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.make

    operations.each do |op|
      transfer_96_to_384(
        op,
        components,
        [PLATE_A, PLATE_B, PLATE_C, PLATE_D],
        PLATE_TRANSFER_MAP,
        SAMPLE_PLATE
      )
    end

    {}

  end
end
