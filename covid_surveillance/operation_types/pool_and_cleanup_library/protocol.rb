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
needs 'Composition Libs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

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
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions

 #========== Composition Definitions ==========#

  STAGED_POOLED_PLATE = 'Pooling Plate'.freeze
  KIT_SAMPLE_NAME = 'Library Pooling Kit'
  POOLED_PLATE = 'TAG Sample Plate'
  DILUTED_ETHANOL = 'EtOH Mix'
  POOLED_LIBRARY = 'Final Pool'
  INITIAL_POOL = "<b>Pooled ITB Tube</b>"

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 4.58, units: MICROLITERS,
         sample_name: nil
       },
       {
         input_name: WATER,
         qty: 400, units: MICROLITERS,
         sample_name: WATER,
         suggested_ot: 'Reagent Bottle'
      },
      {
        input_name: DILUTED_ETHANOL,
        qty: nil, units: MICROLITERS,
        sample_name: ETOH,
        suggested_ot: 'Reagent Bottle'
      },
      {
        input_name: POOLED_LIBRARY,
        qty: 50, units: MICROLITERS,
        sample_name: POOLED_LIBRARY,
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
        consumable: CONSUMABLES[MICRO_TUBE],
        qty: 2, units: 'Tubes'
      },
      {
        consumable: CONSUMABLES[PLATE],
        qty: 1, units: 'Each'
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
    mosquito_robot_program: 'Pool and Clean Up Libraries',
    mosquito_robot_model: Mosquito::MODEL,
    re_transfer_volume: create_qty(qty: 50, units: MICROLITERS),
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') },
    incubation_params2: { time: create_qty(qty: 2, units: MINUTES),
                          temperature: create_qty(qty: 'room temperature',
                                                  units: '') }
  }
end

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

      plate = op.input(POOLED_PLATE).collection

      required_reactions = create_qty(qty: plate.parts.length,
                                      units: 'rxn')

      composition, consumables, _kit_ = setup_kit_composition(
        kit_sample_names: [KIT_SAMPLE_NAME],
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumable_data
      )

      composition.input(POOLED_LIBRARY).item = op.output(POOLED_LIBRARY).item
      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection

      plate_display = composition.input(POOLED_PLATE).display_name

      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).suggested_ot
      )

      retrieve_items = reject_components(
        list_of_rejections: [POOLED_PLATE, DILUTED_ETHANOL, POOLED_LIBRARY],
        components: composition.components
      )

      display(
        title: 'Retrieve Materials',
        show_block: [retrieve_materials(retrieve_items + consumables.consumables,
                                        adj_qty: true)]
      )

      vortex_list = [composition.input(ITB), composition.input(RSB_HT)]

      show_block_1a = (shake(items: vortex_list.map(&:display_name),
                             type: Vortex::NAME))

      show_block_1b = prepare_etoh(etho: composition.input(DILUTED_ETHANOL),
                                   abs_eth: composition.input(ETOH),
                                   water: composition.input(WATER))

      show_block_1c = place_on_magnet(plate_display, time_min: 3)

      show_block_1e = label_items(objects: [consumables.input(MICRO_TUBE),
                                            consumables.input(PLATE)],
                                  labels: [INITIAL_POOL, 'Pooled Sample Plate'])
      display_hash(
        title: 'Prepare Components',
        hash_to_show: [
          show_block_1a,
          show_block_1b,
          show_block_1c,
          show_block_1e
        ]
      )

      mosquito_program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_robot_program]
      )

      mosquito_robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot_model],
        name: op.temporary[:mosquito_robot_model],
        protocol: self
      )

      show_block_2a = use_robot(
        program: mosquito_program,
        robot: mosquito_robot,
        items: ['Pooled Sample Plate',
                composition.input(POOLED_PLATE)]
      )

      show_block_2b = pipet(volume: {qty: 35, units: MICROLITERS},
                            source: composition.input(POOLED_PLATE),
                            destination: 'Pooled Sample Plate')

      display_hash(
        title: 'Pool Wells',
        hash_to_show: [
          show_block_2a,
          "Use a <b>P200</b> pipette to transfer <b>35 #{MICROLITERS}</b> from every well of #{composition.input(POOLED_PLATE)} to  Pooled Sample PLate"
        ]
      )

      association_map = one_to_one_association_map(from_collection: plate)

      associate_transfer_collection_to_item(
        from_collection: plate,
        to_item: composition.input(POOLED_LIBRARY).item,
        association_map: association_map,
        transfer_vol: composition.input(POOLED_PLATE).volume_hash)

      show_block_3a = shake(
        items: ["<b>#{INITIAL_POOL}</b>", composition.input(ITB).display_name],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      )

      show_block_3b = pipet(
        volume: composition.input(ITB).volume_hash,
        source: composition.input(ITB),
        destination: INITIAL_POOL
      )

      show_block_3c = shake(
        items: [INITIAL_POOL],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      )

      show_block_3d =show_incubate_items(
        items: [INITIAL_POOL],
        time: temporary_options[:incubation_params][:time],
        temperature: temporary_options[:incubation_params][:temperature]
      )

      show_block_3e = spin_down(
        items: [INITIAL_POOL],
        speed: temporary_options[:centrifuge_parameters][:speed],
        time: temporary_options[:centrifuge_parameters][:time]
      )

      show_block_3f = place_on_magnet(INITIAL_POOL, time_min: 5)

      show_block_3g = remove_item_supernatant([INITIAL_POOL])

      show_block_3h = wash_beads(INITIAL_POOL)

      show_block_3i = wash_beads(INITIAL_POOL)

      show_block_4a = remove_from_magnet(INITIAL_POOL)

      show_block_4b = pipet(
        volume: composition.input(RSB_HT).volume_hash,
        source: composition.input(RSB_HT),
        destination: INITIAL_POOL
      )

      show_block_4c = shake(
        items: [INITIAL_POOL],
        type: Vortex::NAME
      )

      show_block_4d = "Briefly centrifuge #{INITIAL_POOL}"

      show_block_4e = show_incubate_items(
        items: [INITIAL_POOL],
        time: temporary_options[:incubation_params2][:time],
        temperature: temporary_options[:incubation_params2][:temperature]
      )

      show_block_4f = place_on_magnet(INITIAL_POOL, time_min: 2)

      show_block_4g = label_items(
        objects: [consumables.input(MICRO_TUBE)],
        labels: [composition.input(POOLED_LIBRARY)]
      )

      show_block_4h = pipet(volume: composition.input(POOLED_LIBRARY).volume_hash,
                            source: INITIAL_POOL,
                            destination: composition.input(POOLED_LIBRARY))

      display_hash(
        title: 'Clean up Library (1:3)',
        hash_to_show: [
          show_block_3a,
          show_block_3b,
          show_block_3c,
          show_block_3d,
        ]
      )

      display_hash(
        title: 'Clean up Library (2:3)',
        hash_to_show: [
          show_block_3e,
          show_block_3f,
          show_block_3g,
          show_block_3h,
          show_block_3i
        ]
      )

      display_hash(
        title: 'Clean up Library (3:3)',
        hash_to_show: [
          show_block_4a,
          show_block_4b,
          show_block_4c,
          show_block_4d,
          show_block_4e,
          show_block_4f,
          show_block_4g,
          show_block_4h
        ]
      )

      composition.input(DILUTED_ETHANOL).item.mark_as_deleted

    end

    {}
  end

  # Directions to wash beads
  #
  # @param item [composition]
  def wash_beads(item)
    show_block = [
      "Place #{item} on the magnetic stand and add 1000 l fresh 80% EtOH",
      'Wait for 30 Seconds'
    ]

    show_block + remove_item_supernatant([INITIAL_POOL])
  end

  # Instructions to prepare EtOH
  #
  # @param comp [Component] the EtOH component
  def prepare_etoh(etho:, abs_eth:, water:)
    oh_vol = abs_eth.volume_hash
    water_vol = water.volume_hash

    etho.item = make_item(sample: etho.sample, object_type: etho.suggested_ot)

    show_block = ["Prepare 80% EtOH from Absolute EtOH #{etho}"]
    show_block.append("Label a #{etho.suggested_ot} with #{etho}")
    show_block.append(pipet(volume: oh_vol,
                            source: abs_eth.display_name,
                            destination: etho))
    show_block.append(pipet(volume: water_vol,
                            source: water.display_name,
                            destination: etho))
    show_block
  end


  # sets up the test
  #
  # @param op [Operation]
  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_empty.length, sample)
    plate.add_samples(samples)
  end

end
