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

# ============= Composition Definitions -==============#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  AMPLIFY_KIT = 'Amplify RNA Kit'

  IPM_HT = 'Illumina PCR Mix HT'
  CPP1_HT = 'COVIDSeq Primer Pool 1 HT'
  CPP2_HT = 'COVIDSeq Primer Pool 2 HT'
  WATER = 'Nuclease-free water'


  TEST_TUBE = '15 ml Tube'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 5, units: MICROLITERS,
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
        input_name: AMPLIFY_KIT,
        qty: 1, units: 'kits',
        description: 'Kit for annealing cDNA',
        location: 'M80 Freezer',
        components: [
          {
            input_name: IPM_HT,
            qty:  12.5, units: MICROLITERS,
            sample_name: IPM_HT,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: CPP1_HT,
            qty: 3.58, units: MICROLITERS,
            sample_name: CPP1_HT,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: CPP2_HT,
            qty: 3.58, units: MICROLITERS,
            sample_name: CPP2_HT,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: WATER,
            qty: 3.91, units: MICROLITERS,
            sample_name: WATER,
            object_type: 'Reagent Bottle'
          }
        ],
        consumables: [
          {
            input_name: TEST_TUBE,
            qty: 1, units: 'Each',
            description: TEST_TUBE
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

COV1 = 'COV1'.freeze
COV2 = 'COV2'.freeze

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

  paired_ops.make

  paired_ops.each do |op|
    set_up_test(op) if debug

    date = DateTime.now.strftime('%Y-%m-%d')
    file_name = "#{date}_Op_#{op.id}_Plate_#{op.input(POOLED_PLATE).collection.id}"

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

    # check compatability for all three plates
    unless check_robot_compatibility(input_object: op.input(POOLED_PLATE).collection,
                                     robot: robot,
                                     program: program)
      remove_unpaired_operations([op])
      next
    end

    composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
    input_plate = composition.input(POOLED_PLATE).item
    plate1 = op.output(COV1).collection
    plate2 = op.output(COV2).collection

    show_get_composition(composition: composition)

    retrieve_materials([input_plate])

    shake(items: composition.kits.map { |kit|
      kit.composition.components.map(&:input_name)
    }.flatten)

    composition.make_kit_component_items

    robot.turn_on

    go_to_instrument(instrument_name: robot.model_and_name)

    robot.select_program_template(program: program)

    robot.save_run(path: program.run_file_path, file_name: file_name)

    robot.follow_template_instructions

    wait_for_instrument(instrument_name: robot.model_and_name)

    robot.remove_item(item: input_plate)
    robot.remove_item(item: plate1)
    robot.remove_item(item: plate2)

    association_map = one_to_one_association_map(from_collection: input_plate)
    [plate1, plate2].each do |plate|
      pp_comp = composition.input(POOLED_PLATE)
      transfer_from_collection_to_collection(from_collection: input_plate,
                                             to_collection: plate,
                                             association_map: association_map,
                                             transfer_vol: pp_comp.qty)
      composition.input(AMPLIFY_KIT).components.each do |comp|
        associate_transfer_item_to_collection(
          from_item: comp.item,
          to_collection: plate,
          association_map: association_map,
          transfer_vol: comp.qty
        )
      end
    end

    seal_plate(plate1, seal: composition.input(AREA_SEAL).input_name)
    seal_plate(plate2, seal: composition.input(AREA_SEAL).input_name)

    shake(items: [plate1, plate2],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time])

    spin_down(items: [plate1, plate2],
              speed: temporary_options[:centrifuge_parameters][:speed],
              time: temporary_options[:centrifuge_parameters][:time])

    store_items([plate1, plate2], location: temporary_options[:storage_location])
    trash_object([input_plate,
                  composition.kits.map { |k| k.components.map(&:item) }].flatten)
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
