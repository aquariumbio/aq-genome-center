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
needs 'Covid Surveillance/CovidSurveillanceHelper'
needs 'Liquid Robot Helper/RobotHelper'

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'PCR Protocols/RunThermocycler'

needs 'Container/ItemContainer'
needs 'Container/KitHelper'


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
  include KitHelper
  include CovidSurveillanceHelper

# ============= Composition Definitions -==============#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  AMPLIFY_KIT = 'Amplify cDNA Kit'

  IPM_HT = 'Illumina PCR Mix HT'
  CPP1_HT = 'COVIDSeq Primer Pool 1 HT'
  CPP2_HT = 'COVIDSeq Primer Pool 2 HT'
  WATER = 'Nuclease-free water'


  TEST_TUBE = '15 ml Reagent Tube'

  MASTER_MIX_2 = 'Master Mix 2'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 5, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       },
       {
         input_name: MASTER_MIX,
         qty: 20, units: MICROLITERS,
         sample_name: MASTER_MIX,
         object_type: TEST_TUBE
       },
       {
        input_name: MASTER_MIX_2,
        qty: 20, units: MICROLITERS,
        sample_name: MASTER_MIX,
        object_type: TEST_TUBE
       },
       {
        input_name: COV1,
        qty: nil, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        object_type: '96-Well Plate'
      },
      {
        input_name: COV2,
        qty: nil, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        object_type: '96-Well Plate'
      },
      {
        input_name: WATER,
        qty: 3.91, units: MICROLITERS,
        sample_name: WATER,
        object_type: 'Reagent Bottle'
      }
    ]
  end

  def consumables
    [
      {
        input_name: AREA_SEAL,
        qty: 1, units: 'Each',
        description: 'Adhesive Plate Seal'
      },
      {
        input_name: TEST_TUBE,
        qty: 2, units: 'Each',
        description: TEST_TUBE
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
    robot_model: TestLiquidHandlingRobot::MODEL,
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

COV1 = 'COV1'.freeze
COV2 = 'COV2'.freeze

########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.make

    operations.each do |op|
      set_up_test(op) if debug

      temporary_options = op.temporary[:options]

      required_reactions = create_qty(qty: op.input(POOLED_PLATE).collection.parts.length,
                                      units: 'rxn')

      composition, kit = setup_kit_composition(
        kit_sample_name: AMPLIFY_KIT,
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumables
      )

      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).object_type
      )

      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      composition.input(COV1).item = op.output(COV1).collection
      composition.input(COV2).item = op.output(COV2).collection
      input_plate = composition.input(POOLED_PLATE).item
      plate1 = composition.input(COV1).item
      plate2 = composition.input(COV2).item

      retrieve_list = reject_components(
        list_of_rejections: [COV1, COV2, MASTER_MIX, MASTER_MIX_2],
        components: composition.components
      )
      show_retrieve_parts(retrieve_list + composition.consumables)

      vortex_list = reject_components(
        list_of_rejections: [POOLED_PLATE, WATER],
        components: retrieve_list
      )

      show_block_1a = shake(items: vortex_list,
                            type: Vortex::NAME)

      adj_multiplier = plate1.get_non_empty.length
      mm_components_1 = [composition.input('IPM_HT'),
                         composition.input('CPP1_HT'),
                         composition.input(WATER)]
      mm_components_2 = [composition.input('IPM_HT'),
                         composition.input('CPP2_HT'),
                         composition.input(WATER)]

      show_block_1b = master_mix_handler(components: mm_components_1,
                                         mm: composition.input(MASTER_MIX),
                                         adjustment_multiplier: adj_multiplier,
                                         mm_container: composition.input(TEST_TUBE))

      show_block_1c = master_mix_handler(components: mm_components_2,
                                         mm: composition.input(MASTER_MIX_2),
                                         adjustment_multiplier: adj_multiplier,
                                         mm_container: composition.input(TEST_TUBE))

      show do
        title 'Prepare for Procedure'
        note show_block_1a.flatten
        separator
        note show_block_1b.flatten
        separator
        note show_block_1c.flatten
      end

      program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:robot_program]
      )

      robot = LiquidRobotFactory.build(model: temporary_options[:robot_model],
                                      name: op.temporary[:robot_model],
                                      protocol: self)
      show_block_2 = []
      show_block_2.append(robot.turn_on)
      show_block_2.append(robot.select_program_template(program: program))
      show_block_2.append(robot.follow_template_instructions)
      show_block_2.append(wait_for_instrument(instrument_name: robot.model_and_name))
      show do
        title 'Set Up and Run Robot'
        bullet show_block_2.flatten
      end

      association_map = one_to_one_association_map(from_collection: input_plate)

      copy_wells(from_collection: input_plate,
                to_collection: plate1,
                association_map: association_map)

      copy_wells(from_collection: input_plate,
                to_collection: plate2,
                association_map: association_map)

      associate_transfer_item_to_collection(
        from_item: composition.input(MASTER_MIX).item,
        to_collection: plate1,
        association_map: association_map,
        transfer_vol: composition.input(MASTER_MIX).volume_hash
      )

      associate_transfer_collection_to_collection(
        from_collection: input_plate,
        to_collection: plate1,
        association_map: association_map,
        transfer_vol: composition.input(POOLED_PLATE).volume_hash
      )

      associate_transfer_item_to_collection(
        from_item: composition.input(MASTER_MIX_2).item,
        to_collection: plate2,
        association_map: association_map,
        transfer_vol: composition.input(MASTER_MIX_2).volume_hash
      )

      associate_transfer_collection_to_collection(from_collection: input_plate,
                                                  to_collection: plate2,
                                                  association_map: association_map,
                                                  transfer_vol: composition.input(POOLED_PLATE).volume_hash)

      kit.remove_volume(required_reactions)

      show_block_3a = []
      show_block_3a.append(seal_plate(
        [plate1, plate2], seal: composition.input(AREA_SEAL).input_name
      ))

      show_block_3b = []
      show_block_3b.append(shake(
        items: [plate1, plate2],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      ))

      show_block_3c = []
      show_block_3c.append(spin_down(
        items: [plate1, plate2],
        speed: temporary_options[:centrifuge_parameters][:speed],
        time: temporary_options[:centrifuge_parameters][:time]
      ))

      show do
        title 'Prepare for Thermocycler'
        note show_block_3a.flatten
        separator
        note show_block_3b.flatten
        separator
        note show_block_3c.flatten
      end
      run_qpcr(op: op,
               plates: [composition.input(COV1).item, composition.input(COV2).item])
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
