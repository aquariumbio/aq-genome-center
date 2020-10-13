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


#========== Composition Definitions ==========#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  FIRST_STRAND_KIT = 'Synthesize First Strand cDNA Kit'

  FSM_HT = 'First Strand Mix HT'
  RVT_HT = 'Reverse Transcriptase HT'

  MICRO_TUBES = '1.7 ml Tube'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       }
    ]
  end

  def consumables
    [
      {
        input_name: AREA_SEAL,
        qty: 1, units: 'Each',
        description: 'Adhesive Plate Seal'
      }
    ]
  end

  def kits
    [
      {
        input_name: FIRST_STRAND_KIT,
        qty: 1, units: 'kits',
        description: 'Kit for synthesizing first strand cDNA',
        location: 'M80 Freezer',
        components: [
          {
            input_name: FSM_HT,
            qty: 7.2, units: MICROLITERS,
            sample_name: 'First Strand Mix HT',
            object_type: 'Reagent Bottle'
          },
          {
            input_name: RVT_HT,
            qty: 0.8, units: MICROLITERS,
            sample_name: 'Reverse Transcriptase HT',
            object_type: 'Reagent Bottle'
          }
        ],
        consumables: [
          {
            input_name: MICRO_TUBES,
            qty: 1, units: 'Each',
            description: '1.7 ml Tube'
          }
        ]
      }
    ]
  end

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

    composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
    plate = composition.input(POOLED_PLATE).item
    op.pass(POOLED_PLATE)

    show_get_composition(composition: composition)

    retrieve_materials([plate])

    vortex_objs(composition.kits.map { |kit|
      kit.composition.components.map(&:input_name)
    }.flatten)

    composition.make_kit_component_items

    robot.turn_on

    go_to_instrument(instrument_name: robot.model_and_name)

    robot.select_program_template(program: program)

    robot.save_run(path: program.run_file_path, file_name: file_name)

    robot.follow_template_instructions

    wait_for_instrument(instrument_name: robot.model_and_name)

    robot.remove_item(item: plate)

    association_map = one_to_one_association_map(from_collection: plate)

    first_strand_comp = composition.input(FIRST_STRAND_KIT).input(FSM_HT)
    rt_component = composition.input(FIRST_STRAND_KIT).input(RVT_HT)

    associate_transfer_item_to_collection(
      from_item: first_strand_comp.item,
      to_collection: plate,
      association_map: association_map,
      transfer_vol: first_strand_comp.qty
    )

    associate_transfer_item_to_collection(
      from_item: rt_component.item,
      to_collection: plate,
      association_map: association_map,
      transfer_vol: rt_component.qty
    )

    seal_plate(plate, seal: composition.input(AREA_SEAL).input_name)

    shake(items: [plate],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time])

    spin_down(items: [plate],
              speed: temporary_options[:centrifuge_parameters][:speed],
              time: temporary_options[:centrifuge_parameters][:time])

    store_items([plate], location: temporary_options[:storage_location])

    trash_object(composition.kits.map { |k| k.components.map(&:item) }.flatten)
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
