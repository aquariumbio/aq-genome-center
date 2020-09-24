# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Standard Libs/Units'

needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'

needs 'Liquid Robot Helper/RobotHelper'

needs 'Microtiter Plates/MicrotiterPlates'


class Protocol
  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper


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
    storage_location: 'M80'
  }
end

########## MAIN ##########

def main
  set_up_test(operations)
  @job_params = update_all_params(
    operations: operations,
    default_job_params: default_job_params,
    default_operation_params: default_operation_params
  )

  paired_ops = pair_ops_with_instruments(operations: operations,
                                         instrument_key: LIQUID_ROBOT_PARAM)

  remove_unpaired_operations(operations - paired_ops)

  paired_ops.each do |op|
    date = DateTime.now.strftime('%Y-%m-%d')
    file_name = "#{date}_Op_#{op.id}_Plate_#{op.input(POOLED_PLATE).collection.id}"

    temporary_options = op.temporary[:options]

    program = LiquidRobotProgramFactory.build(
      program_name: temporary_options[:robot_program]
    )

    robot = LiquidRobotFactory.build(model: temporary_options[:instrument_model],
                                     name: op.temporary[INSTRUMENT_NAME],
                                     protocol: self)

    unless check_robot_compatibility(input_object: op.input(POOLED_PLATE).collection,
                                     robot: robot,
                                     program: program)
      remove_unpaired_operations([op])
      next
    end

    robot.turn_on

    op.pass(POOLED_PLATE)

    plate = op.output(POOLED_PLATE).collection

    retrieve_materials([plate])

    go_to_instrument(instrument_name: robot.model_and_name)

    robot.check_supplies(items: nil, consumables: [{obj: 'Pipette Tips',
                         qty: create_qty(qty: 300, units: 'Each')}])

    robot.place_item(item: plate)

    robot.confirm_orientation

    robot.select_program_template(program: program)

    robot.save_run(path: program.run_file_path, file_name: file_name)

    robot.start_run

    wait_for_instrument(instrument_name: robot.model_and_name)

    robot.remove_item(item: plate)

    store_items([plate], location: temporary_options[:storage_location])
  end

  {}

end

  def set_up_test(operations)
    operations.each do |op|
      sample = op.input(POOLED_PLATE).item.sample
      plate = op.input(POOLED_PLATE).collection
      samples = Array.new(plate.get_non_empty.length, sample)
      plate.add_samples(samples)
    end
  end

end
