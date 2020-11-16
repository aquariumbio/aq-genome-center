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

needs 'PCR Protocols/RunThermocycler'


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
  include RunThermocycler

  #========== Composition Definitions ==========#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  FIRST_STRAND_KIT = 'Synthesize First Strand cDNA Kit'

  FSM_HT = 'First Strand Mix HT'
  RVT_HT = 'Reverse Transcriptase HT'

  MICRO_TUBES = '1.7 ml Reagent Tube'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: nil,
         object_type: nil
       },
       {
         input_name: MASTER_MIX,
         qty: 8, units: MICROLITERS,
         sample_name: MASTER_MIX,
         object_type: MICRO_TUBES
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
            qty: 9, units: MICROLITERS,
            sample_name: 'First Strand Mix HT',
            object_type: 'Reagent Bottle'
          },
          {
            input_name: RVT_HT,
            qty: 1, units: MICROLITERS,
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
                             speed: create_qty(qty: 1000, units: TIMES_G) },
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'CDC_TaqPath_CG',
    qpcr: true
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

    adj_multiplier = plate.get_non_empty.length
    mm_components = [composition.input(FIRST_STRAND_KIT).input(FSM_HT),
                     composition.input(FIRST_STRAND_KIT).input(RVT_HT)]
    adjust_volume(components: mm_components,
                  multi: adj_multiplier)

    mm = composition.input(MASTER_MIX)

    mm.item = make_item(sample: mm.sample,
                        object_type: mm.object_type)

    label_items(objects: [composition.input(FIRST_STRAND_KIT).input(MICRO_TUBES).input_name],
                labels: [mm.item])

    create_master_mix(components: mm_components,
                      master_mix_item: mm.item,
                      adj_qty: true)

    robot.turn_on

    go_to_instrument(instrument_name: robot.model_and_name)

    robot.select_program_template(program: program)

    robot.save_run(path: program.run_file_path, file_name: file_name)

    robot.follow_template_instructions

    wait_for_instrument(instrument_name: robot.model_and_name)

    robot.remove_item(item: plate)

    association_map = one_to_one_association_map(from_collection: plate)

    associate_transfer_item_to_collection(
      from_item: composition.input(MASTER_MIX).item,
      to_collection: plate,
      association_map: association_map,
      transfer_vol: composition.input(MASTER_MIX).volume_hash
    )

    seal_plate(plate, seal: composition.input(AREA_SEAL).input_name)

    shake(items: [plate],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time])

    spin_down(items: [plate],
              speed: temporary_options[:centrifuge_parameters][:speed],
              time: temporary_options[:centrifuge_parameters][:time])

    trash_object(composition.kits.map { |k| k.components.map(&:item) }.flatten)
  end

  run_qpcr(operations: operations, item_key: POOLED_PLATE)

  {}

end

def set_up_test(op)
  sample = op.input(POOLED_PLATE).part.sample
  plate = op.input(POOLED_PLATE).collection
  samples = Array.new(plate.get_non_empty.length, sample)
  plate.add_samples(samples)
end

end
