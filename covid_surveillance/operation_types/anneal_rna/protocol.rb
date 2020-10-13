# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Standard Libs/Units'
needs 'Standard Libs/CommonInputOutputNames'

needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/AnnealRNACompositionDefinitions'

needs 'Liquid Robot Helper/RobotHelper'

#needs 'Microtiter Plates/MicrotiterPlates'

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionActions'
needs 'Collection Management/CollectionTransfer'

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
  include CommonInputOutputNames
  include AnnealRNACompositionDefinitions
  include CompositionHelper
  include CollectionActions
  include CollectionTransfer

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
    robot_program: 'abstract program',
    instrument_model: TestLiquidHandlingRobot::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                        speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                            speed: create_qty(qty: 1000, units: TIMES_G) }
  }
end

########## MAIN ##########

def main
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
    file_name = "#{date}_Job_#{op.jobs.ids.last}_Op_#{op.id}_Plan_#{op.plan.id}"

    set_up_test(op) if debug
    temporary_options = op.temporary[:options]

    composition = CompositionFactory.build(components: components,
                                           consumables: consumables,
                                           kits: kits)

    robot_program = LiquidRobotProgramFactory.build(
      program_name: temporary_options[:robot_program]
    )

    robot = LiquidRobotFactory.build(model: temporary_options[:instrument_model],
                                     name: op.temporary[INSTRUMENT_NAME],
                                     protocol: self)

    unless check_robot_compatibility(input_object: op.input(POOLED_PLATE).collection,
                                     robot: robot,
                                     program: robot_program)
      remove_unpaired_operations([op])
      next
    end

    composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection

    plate = composition.input(POOLED_PLATE).item
    op.output(POOLED_PLATE).make_collection
    cdna = op.output(POOLED_PLATE).collection

    show_get_composition(composition: composition)

    get_and_label_new_plate(cdna)

    retrieve_materials([plate])

    vortex_objs(composition.kits.map{ |kit|
      kit.composition.components.map(&:input_name)
    }.flatten)

    composition.make_kit_component_items

    go_to_instrument(instrument_name: robot.model_and_name)

    robot.turn_on

    robot.select_program_template(program: robot_program)

    robot.save_run(path: robot_program.run_file_path, file_name: file_name)

    robot.follow_template_instructions

    wait_for_instrument(instrument_name: robot.model_and_name)

    robot.remove_item(item: plate)
    robot.remove_item(item: cdna)

    association_map = one_to_one_association_map(from_collection: plate)
    copy_wells(from_collection: plate, 
               to_collection: cdna,
               association_map: association_map)

    associate_transfer_collection_to_collection(
      from_collection: plate,
      to_collection: cdna,
      association_map: association_map,
      transfer_vol: composition.input(POOLED_PLATE).qty
    )

    eph_component = composition.input(ANNEAL_KIT).input(EPH_HT)
    associate_transfer_item_to_collection(
      from_item: eph_component.item,
      to_collection: cdna,
      association_map: association_map,
      transfer_vol: eph_component.qty
    )

    seal_plate(cdna, seal: composition.input(AREA_SEAL).input_name)

    shake(items: [plate],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time])

    spin_down(items: [plate],
              speed: temporary_options[:centrifuge_parameters][:speed],
              time: temporary_options[:centrifuge_parameters][:time])

    store_items([cdna], location: temporary_options[:storage_location])
    trash_object([plate,
                  composition.kits.map{ |k| k.components.map(&:item) }].flatten)
  end

  {}

end

  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_non_empty.length, sample)
    plate.add_samples(samples)
  end

end
