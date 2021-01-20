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

needs 'Composition Libs/Composition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'PCR Protocols/RunThermocycler'

needs 'Container/ItemContainer'
needs 'Container/KitHelper'
needs 'Kits/KitContents'

needs 'Consumable Libs/Consumables'
needs 'Consumable Libs/ConsumableDefinitions'

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
  include KitContents
  include ConsumableDefinitions

# ============= Composition Definitions -==============#

  AMPLIFY_KIT = 'Amplify cDNA Kit'

  MASTER_MIX_2 = 'Master Mix 2'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 5, units: MICROLITERS,
         sample_name: 'Pooled Specimens'
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
        sample_name: 'Pooled Specimens'
      },
      {
        input_name: COV2,
        qty: nil, units: MICROLITERS,
        sample_name: 'Pooled Specimens'
      },
      {
        input_name: WATER,
        qty: 3.91, units: MICROLITERS,
        sample_name: WATER,
        suggested_ot: 'Reagent Bottle'
      }
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[AREA_SEAL],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TEST_TUBE],
        qty: 2, units: 'Each'
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
    mosquito_robot_program: 'Amplify CDNA',
    mosquito_robot_model: Mosquito::MODEL,
    dragonfly_robot_program: 'PCR 1 MM',
    dragonfly_robot_program2: 'PCR 2 MM',
    dragonfly_robot_model: Dragonfly::MODEL,
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

      composition, consumables, kit = setup_kit_composition(
        kit_sample_name: AMPLIFY_KIT,
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumable_data
      )

      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).suggested_ot
      )

      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      composition.input(COV1).item = op.output(COV1).collection
      composition.input(COV2).item = op.output(COV2).collection
      input_plate = composition.input(POOLED_PLATE).item
      plate1 = composition.input(COV1).item
      plate2 = composition.input(COV2).item

      retrieve_list = reject_components(
        list_of_rejections: [POOLED_PLATE, COV1, COV2,
                             MASTER_MIX, MASTER_MIX_2],
        components: composition.components
      )
      show_retrieve_parts(retrieve_list + consumables.consumables)

      vortex_list = reject_components(
        list_of_rejections: [POOLED_PLATE, WATER],
        components: retrieve_list
      )

      show_block_1a = shake(items: vortex_list,
                            type: Vortex::NAME)

      adj_multiplier = plate1.get_non_empty.length
      mm_components_1 = [composition.input(IPM_HT),
                         composition.input(CPP1_HT),
                         composition.input(WATER)]
      mm_components_2 = [composition.input(IPM_HT),
                         composition.input(CPP2_HT),
                         composition.input(WATER)]

      show_block_1b = master_mix_handler(components: mm_components_1,
                                         mm: composition.input(MASTER_MIX),
                                         adjustment_multiplier: adj_multiplier,
                                         mm_container: composition.input(TEST_TUBE))

      show_block_1c = master_mix_handler(components: mm_components_2,
                                         mm: composition.input(MASTER_MIX_2),
                                         adjustment_multiplier: adj_multiplier,
                                         mm_container: composition.input(TEST_TUBE))

      display_hash(
        title: 'Prepare for Procedure',
        hash_to_show: [
          show_block_1a,
          show_block_1b,
          show_block_1c
        ]
      )

      drgprogram = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program]
      )
      drgprogram2 = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program2]
      )

      drgrobot = LiquidRobotFactory.build(
        model: temporary_options[:dragonfly_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      display_hash(
        title: 'Set Up and Run Robot',
        hash_to_show: use_robot(program: drgprogram,
                                robot: drgrobot,
                                items: [plate1,
                                        composition.input(MASTER_MIX)])
      )

      display_hash(
        title: 'Set Up and Run Robot',
        hash_to_show: use_robot(program: drgprogram2,
                                robot: drgrobot,
                                items: [plate2,
                                        composition.input(MASTER_MIX_2)])
      )

      program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_robot_program]
      )

      robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      display_hash(
        title: 'Set Up and Run Robot',
        hash_to_show: use_robot(program: program,
                                robot: robot, items: [input_plate,
                                                      plate1, plate2])
      )

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
        [plate1, plate2], seal: consumables.input(AREA_SEAL)
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

      display_hash(
        title: 'Prepare for Thermocycler',
        hash_to_show: [
          show_block_3a,
          show_block_3b,
          show_block_3c
        ]
      )

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
