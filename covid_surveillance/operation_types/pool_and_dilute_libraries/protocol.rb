# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Small Instruments/Centrifuges'
needs 'Small Instruments/Shakers'
needs 'Standard Libs/Units'
needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Liquid Robot Helper/RobotHelper'

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'


class Protocol
  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Centrifuges
  include Shakers
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CompositionHelper
  include CollectionTransfer
  include CollectionActions


########## DEFAULT PARAMS ##########

# Default parameters that are applied equally to all operations.
#   Can be overridden by:
#   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
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
    robot_program: 'abstract program',
    instrument_model: TestLiquidHandlingRobot::MODEL,
  }
end

  ########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )
    unless valid_operations(operations)
      bounce_ops(operations)
      return {}
    end

  end

  # validates that the operations are compatible
  #
  # @param operations [OperationList]
  def valid_operations(operations)
    return false if operations.length > 4
    warn_number_of_ops(operations.length) unless operations.length == 4
  end

  def warn_number_of_ops(num_ops)
    show do
      title 'Wrong number of operations'
      note  'Are you sure you want to continue?'
      note "Only #{operations.length} are planned when 4 should be run together"
      separator
      note 'Click <b>OK</b> to continue'
      note 'Click <b>Cancel</b> to cancel'
    end
  end

  # bounces operations back to pending
  #
  # @param operations |Array<operations>|
  def bounce_ops(operations)
    operations.each do |op|
      op.error('incompatible index adapters')
      op.status = 'pending'
      op.save
    end
  end

end