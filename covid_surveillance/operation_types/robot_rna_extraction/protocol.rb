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

needs 'Composition Libs/Composition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'Container/KitHelper'
needs 'Kits/KitContents'

needs 'Consumable Libs/Consumables'
needs 'Consumable Libs/ConsumableDefinitions'

needs 'Covid Surveillance/CovidSurveillanceHelper'

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
  include KitHelper
  include KitContents
  include CovidSurveillanceHelper

  # ============= Composition Definitions ==============#
  EXTRACTION_KIT = 'QiAmp 96 Viral RNA Kit'

  ETHANOL = 'Absolute ethanol'

  AVL_AVE_CARRIER = 'Mixed Carrier RNA, AVE, AVL'

  EXTRACTION_PLATE = 'Extracted Sample Plate'
  EXTRACTION_PLATE_2 = 'Extracted Sample Plate 2'
  SBLOCK = 'S-Block'
  SBLOCK_2 = 'S-Block 2'
  POOLED_PLATE_2 = 'Pooled Sample Plate 2'
  QIAAMP_PLATE_2 = QIAAMP_PLATE + ' 2'

  def components
    [
       {
         input_name: POOLED_PLATE,
         qty: 140, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         suggested_ot: '96-Well Plate'
       },
       {
        input_name: POOLED_PLATE_2,
        qty: 140, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        suggested_ot: '96-Well Plate'
       },
       {
         input_name: ETHANOL,
         qty: 560, units: MICROLITERS,
         sample_name: ETHANOL,
         suggested_ot: 'Reagent Bottle'
       },
       {
        input_name: AVL_AVE_CARRIER,
        qty: 560, units: MICROLITERS,
        sample_name: AVL_AVE_CARRIER,
        suggested_ot: 'Reagent Bottle'
      },
      {
        input_name: EXTRACTION_PLATE,
        qty: nil, units: nil,
        sample_name: 'Pooled Specimens',
        suggested_ot: '96-Well Plate'
      },
      {
        input_name: EXTRACTION_PLATE_2,
        qty: nil, units: nil,
        sample_name: 'Pooled Specimens',
        suggested_ot: '96-Well Plate'
      },
      {
        input_name: SBLOCK,
        qty: 630, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        suggested_ot: DEEP_PLATE_96_WELL
      },
      {
        input_name: SBLOCK_2,
        qty: 630, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        suggested_ot: DEEP_PLATE_96_WELL
      },
      {
        input_name: QIAAMP_PLATE,
        qty: nil, units: nil,
        sample_name: 'Pooled Specimens',
        suggested_ot: QIAAMP_PLATE
      },
      {
        input_name: QIAAMP_PLATE_2,
        qty: nil, units: nil,
        sample_name: 'Pooled Specimens',
        suggested_ot: QIAAMP_PLATE
      }
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[DEEP_PLATE_96_WELL],
        qty: 2, units: 'Each'
      },
      {
        consumable: CONSUMABLES[PLATE_96_WELL],
        qty: 2, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TAPE_PAD],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TUBE_500UL],
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
      centrifuge_parameters: { time: create_qty(qty: 4, units: MINUTES),
                               speed: create_qty(qty: 5788, units: TIMES_G),
                               type: Qiagenks::NAME },
      incubation_params: { time: create_qty(qty: 10, units: MINUTES),
                           temperature: create_qty(qty: 'room temperature',
                                                   units: '') },
      buffer_560: '560 ul Buffer Program',
      buffer_500: '500 ul Buffer Program',
      buffer_250: '250 ul Buffer Program',
      buffer_80: '80 ul Buffer Program',
      transfer_630: '630 ul Transfer Program',
      transfer_to_s_block: '140 ul S-block Transfer',
      dragonfly_robot: Dragonfly::MODEL,
      mosquito_program: 'RNA Extraction',
      mosquito_robot: Mosquito::MODEL
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
    set_up_test(operations) if debug

    operations.each do |op|

      temporary_options = op.temporary[:options]

      plate_1 = op.input(POOLED_PLATE).collection
      plate_2 = op.input(POOLED_PLATE_2).collection

      required_reactions = create_qty(
        qty: plate_1.parts.length + plate_2.parts.length,
        units: 'rxn'
      )

      composition, consumables, _kit_ = setup_kit_composition(
        kit_sample_name: EXTRACTION_KIT,
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumable_data
      )

      composition.input(POOLED_PLATE).item = plate_1
      composition.input(POOLED_PLATE_2).item = plate_2
      composition.input(ETHANOL).item = find_random_item(
        sample: composition.input(ETHANOL).sample,
        object_type: composition.input(ETHANOL).suggested_ot
      )

      retrieve_parts = reject_components(
        components: composition.components,
        list_of_rejections: [AVL_AVE_CARRIER, EXTRACTION_PLATE, EXTRACTION_PLATE_2,
                             QIAAMP_PLATE, QIAAMP_PLATE_2, SBLOCK, SBLOCK_2]
      )

      show_retrieve_parts(retrieve_parts + consumables.consumables)

      show_block_1 = make_avl_carrier_master_mix(
        composition: composition,
        consumables: consumables,
        num_rxn: required_reactions[:qty]
      )

      program_560 = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:buffer_560]
      )

      dragonfly_robot = LiquidRobotFactory.build(
        model: temporary_options[:dragonfly_robot],
        name: temporary_options[:dragonfly_robot],
        protocol: self
      )

      mosquito_robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot],
        name: temporary_options[:mosquito_robot],
        protocol: self
      )

      sblock_ctype = consumables.input(DEEP_PLATE_96_WELL).input_name

      composition.input(SBLOCK).item =
        Collection.new_collection(sblock_ctype)
      composition.input(SBLOCK_2).item =
        Collection.new_collection(sblock_ctype)

      show_block_1 = []


      # Label Sblocks
      show_block_1.append(
        [ { display: get_and_label_new_plate(composition.input(SBLOCK).item),
            type: 'note' },
          { display: get_and_label_new_plate(composition.input(SBLOCK_2).item),
            type: 'note'}
        ]
      )

      # add AVL-Carrier to the Sblocks
      show_block_1.append(
        use_robot(
          program: program_560,
          robot: dragonfly_robot,
          items:[composition.input(AVL_AVE_CARRIER),
                 composition.input(SBLOCK),
                 composition.input(SBLOCK_2)]
        )
      )

      sblock_transfer = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:transfer_to_s_block]
      )

      # Move media from sample plate to approperate sblock
      show_block_1.append(
        use_robot(
          program: sblock_transfer,
          robot: mosquito_robot,
          items:[composition.input(POOLED_PLATE),
                 composition.input(SBLOCK)]
        )
      )

      # Move media from sample plate to sblcok
      show_block_1.append(
        use_robot(
          program: sblock_transfer,
          robot: mosquito_robot,
          items:[composition.input(POOLED_PLATE_2),
                 composition.input(SBLOCK_2)]
        )
      )

      # Seal both plates
      show_block_1.append(
        {
          display: seal_plate(
            [composition.input(SBLOCK_2),
             composition.input(SBLOCK)],
            seal: consumables.input(TAPE_PAD)
          ),
          type: 'note'
        }
      )

      # Incubate plates for some time
      show_block_1.append(
        show_incubate_items(
          items: [composition.input(SBLOCK_2),
                  composition.input(SBLOCK)],
          time: temporary_options[:incubation_params][:time],
          temperature: temporary_options[:incubation_params][:temperature]
        )
      )

      display_hash(
        title: 'RNA Extraction',
        hash_to_show: show_block_1
      )

      show_block_2 = []
      # Remove Seal from both plates
      show_block_2.append(
        {
          display: remove_seal(
            [composition.input(SBLOCK_2),
             composition.input(SBLOCK)],
          ),
          type: 'note'
        }
      )

      # Add Ethanol 560 ml
      show_block_2.append(
        use_robot(
          program: program_560,
          robot: dragonfly_robot,
          items:[composition.input(ETHANOL),
                 composition.input(SBLOCK),
                 composition.input(SBLOCK_2)]
        )
      )

      qiam_ctype = consumables.input(QIAAMP_PLATE).input_name

      composition.input(QIAAMP_PLATE).item =
        Collection.new_collection(qiam_ctype)
      composition.input(QIAAMP_PLATE_2).item =
        Collection.new_collection(qiam_ctype)

      # Label Qiam spin plates
      show_block_2.append(
        [ { display: get_and_label_new_plate(composition.input(QIAAMP_PLATE).item),
            type: 'note' },
          { display: get_and_label_new_plate(composition.input(QIAAMP_PLATE_2).item),
            type: 'note'}
        ]
      )

      display_hash(
        title: 'RNA Extraction',
        hash_to_show: show_block_2
      )

      show_block_3 = []
      #Place on S block
      show_block_3.append(
        {
          display: place_on_s_block(
            qiamp_plates: [composition.input(QIAAMP_PLATE).to_s, 
                          composition.input(QIAAMP_PLATE_2).to_s]
          ),
          type: 'note'
        }
      )

      show_block_3 += transfer_to_qiamp(
        robot: mosquito_robot,
        composition: composition,
        temporary_options: temporary_options,
        consumables: consumables
      )

      display_hash(
        title: 'RNA Extraction',
        hash_to_show: show_block_3
      )

      display_hash(
        title: 'RNA Extraction',
        hash_to_show: transfer_to_qiamp(
          robot: mosquito_robot,
          composition: composition,
          temporary_options: temporary_options,
          consumables: consumables
        )
      )

      show_block_4 = []
      #Place on S block
      show_block_4.append(
        {
          display: place_on_s_block(
            qiamp_plates: [composition.input(QIAAMP_PLATE).to_s,
                           composition.input(QIAAMP_PLATE_2).to_s]
          ),
          type: 'note'
        }
      )

      program500 = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:buffer_500]
      )

      show_block_4.append(
        use_robot(
          program: program500,
          robot: dragonfly_robot,
          items:[composition.input(AW1),
                 composition.input(QIAAMP_PLATE),
                 composition.input(QIAAMP_PLATE_2)]
        )
      )

      # Seal both plates
      show_block_4.append(
        {
          display: seal_plate(
            [composition.input(QIAAMP_PLATE),
            composition.input(QIAAMP_PLATE_2)],
            seal: consumables.input(TAPE_PAD)
          ),
          type: 'note'
        }
      )

      show_block_4.append(
        {
          display: spin_down(
            items: [composition.input(QIAAMP_PLATE).item,
                    composition.input(QIAAMP_PLATE_2).item],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time],
            type: temporary_options[:centrifuge_parameters][:type]
          ),
          type: 'note'
        }
      )

      # Remove Seal from both plates
      show_block_4.append(
        {
          display: remove_seal(
            [composition.input(QIAAMP_PLATE_2),
            composition.input(QIAAMP_PLATE)]
          ),
          type: 'note'
        }
      )

      show_block_4.append(
        use_robot(
          program: program500,
          robot: dragonfly_robot,
          items:[composition.input(AW2),
                 composition.input(QIAAMP_PLATE),
                 composition.input(QIAAMP_PLATE_2)]
        )
      )

      # Seal both plates
      show_block_4.append(
        {
          display: seal_plate(
            [composition.input(QIAAMP_PLATE),
            composition.input(QIAAMP_PLATE_2)],
            seal: consumables.input(TAPE_PAD)
          ),
          type: 'note'
        }
      )

      show_block_4.append(
        {
          display: spin_down(
            items: [composition.input(QIAAMP_PLATE).item,
                    composition.input(QIAAMP_PLATE_2).item],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time],
            type: temporary_options[:centrifuge_parameters][:type]
          ),
          type: 'note'
        }
      )

      # Remove Seal from both plates
      show_block_4.append(
        {
          display: remove_seal(
            [composition.input(QIAAMP_PLATE_2),
            composition.input(QIAAMP_PLATE)]
          ),
          type: 'note'
        }
      )

      display_hash(
        title: 'RNA Extraction',
        hash_to_show: show_block_4
      )

      show_block5 = []

      buffer_250 = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:transfer_630]
      )

      # Add Ethanol 560 ml
      show_block5.append(
        use_robot(
          program: program500,
          robot: dragonfly_robot,
          items:[composition.input(ETHANOL),
                 composition.input(QIAAMP_PLATE),
                 composition.input(QIAAMP_PLATE_2)]
        )
      )

      # Seal both plates
      show_block5.append(
        {
          display: seal_plate(
            [composition.input(QIAAMP_PLATE),
            composition.input(QIAAMP_PLATE_2)],
            seal: consumables.input(TAPE_PAD)
          ),
          type: 'note'
        }
      )

      show_block5.append(
        {
          display: spin_down(
            items: [composition.input(QIAAMP_PLATE).item,
                    composition.input(QIAAMP_PLATE_2).item],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time],
            type: temporary_options[:centrifuge_parameters][:type]
          ),
          type: 'note'
        }
      )

      # Remove Seal from both plates
      show_block5.append(
        {
          display: remove_seal(
            [composition.input(QIAAMP_PLATE_2),
            composition.input(QIAAMP_PLATE)]
          ),
          type: 'note'
        }
      )

      place_on_s_block(qiamp_plates:[composition.input(QIAAMP_PLATE_2),
                                     composition.input(QIAAMP_PLATE)])

      show_block5.append(
        {
          display: spin_down(
            items: [composition.input(QIAAMP_PLATE).item,
                    composition.input(QIAAMP_PLATE_2).item],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: create_qty(qty: 10, units: MINUTES),
            type: temporary_options[:centrifuge_parameters][:type]
          ),
          type: 'note'
        }
      )

      display_hash(
        title: 'RNA Extraction',
        hash_to_show: show_block5
      )

      show_block6 = []

      extraction_plate = composition.input(EXTRACTION_PLATE).suggested_ot

      composition.input(EXTRACTION_PLATE).item =
        Collection.new_collection(extraction_plate)
      composition.input(EXTRACTION_PLATE_2).item =
        Collection.new_collection(extraction_plate)

      # Label Qiam spin plates
      show_block6.append(
        [ { display: get_and_label_new_plate(composition.input(EXTRACTION_PLATE).item),
            type: 'note' },
          { display: get_and_label_new_plate(composition.input(EXTRACTION_PLATE_2).item),
            type: 'note'}
        ]
      )

      show_block6.append(
        {
          display: place_on_plate(from: composition.input(QIAAMP_PLATE),
                                  to: composition.input(EXTRACTION_PLATE)),
          type: 'note'
        }
      )

      show_block6.append(
        {
          display: place_on_plate(from: composition.input(QIAAMP_PLATE_2),
                                  to: composition.input(EXTRACTION_PLATE_2)),
          type: 'note'
        }
      )

      buffer80 = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:buffer_80]
      )

      # Add Ethanol 560 ml
      show_block6.append(
        use_robot(
          program: buffer80,
          robot: dragonfly_robot,
          items:[composition.input(AVE),
                 composition.input(EXTRACTION_PLATE_2),
                 composition.input(EXTRACTION_PLATE)]
        )
      )

      # Incubate plates for some time
      show_block6.append(
        {
          display: show_incubate_items(
            items: [composition.input(EXTRACTION_PLATE_2),
                    composition.input(EXTRACTION_PLATE)],
            time: temporary_options[:incubation_params][:temperature],
            temperature: create_qty(qty: 1, units: MINUTES)
          ),
          type: 'note'
        }
      )

      show_block6.append(
        {
          display: spin_down(
            items: [composition.input(EXTRACTION_PLATE).item,
                    composition.input(EXTRACTION_PLATE_2).item],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: create_qty(qty: 4, units: MINUTES),
            type: temporary_options[:centrifuge_parameters][:type]
          ),
          type: 'note'
        }
      )

      display_hash(
        title: 'RNA Extraction',
        hash_to_show: show_block6
      )
    end
  end

  def place_on_plate(from:, to:)
    "Place <b>#{from}</b> on <b>#{to}</b>e"
  end

  def transfer_to_qiamp(robot:, composition:, temporary_options:, consumables:)
    show_block = []

    transfer_630 = LiquidRobotProgramFactory.build(
      program_name: temporary_options[:transfer_630]
    )

    # Add Ethanol 560 ml
    show_block.append(
      use_robot(
        program: transfer_630,
        robot: robot,
        items:[composition.input(SBLOCK),
               composition.input(QIAAMP_PLATE)]
      )
    )

    # Add Ethanol 560 ml
    show_block.append(
      use_robot(
        program: transfer_630,
        robot: robot,
        items:[composition.input(SBLOCK_2),
               composition.input(QIAAMP_PLATE_2)]
      )
    )

    # Seal both plates
    show_block.append(
      {
        display: seal_plate(
          [composition.input(SBLOCK),
           composition.input(SBLOCK_2)],
          seal: consumables.input(TAPE_PAD)
        ),
        type: 'note'
      }
    )

    show_block.append(
      {
        display: spin_down(
          items: [composition.input(SBLOCK).item,
                  composition.input(SBLOCK_2).item],
          speed: temporary_options[:centrifuge_parameters][:speed],
          time: temporary_options[:centrifuge_parameters][:time],
          type: temporary_options[:centrifuge_parameters][:type]
        ),
        type: 'note'
      }
    )

    # Remove Seal from both plates
    show_block.append(
      {
        display: remove_seal(
          [composition.input(SBLOCK_2),
           composition.input(SBLOCK)]
        ),
        type: 'note'
      }
    )

    show_block
  end

  def place_on_s_block(qiamp_plates:)
    "Place #{qiamp_plates} on FRESH #{DEEP_PLATE_96_WELL}"
  end

  def make_avl_carrier_master_mix(composition:, consumables:, num_rxn:)
    composition.input(AVL).adj_qty = 0.6 * num_rxn * 1000 # ul
    composition.input(AVL).units = MICROLITERS

    composition.input(AVE_CARRIER).adj_qty = 0.6 * num_rxn * 10 # ul
    composition.input(AVE_CARRIER).units = MICROLITERS

    master_mix_components = [composition.input(AVL), composition.input(AVE_CARRIER)]
    master_mix_handler(
      components: master_mix_components,
      mm: composition.input(AVL_AVE_CARRIER),
      mm_container: consumables.input(TUBE_500UL),
      adjustment_multiplier: nil
    )
  end

  def set_up_test(operations)
    operations.each do |op|
      sample = op.input(POOLED_PLATE).part.sample
      plate = op.input(POOLED_PLATE).collection
      samples = Array.new(plate.get_empty.length, sample)
      plate.add_samples(samples)
      sample = op.input(POOLED_PLATE_2).part.sample
      plate = op.input(POOLED_PLATE_2).collection
      samples = Array.new(plate.get_empty.length, sample)
      plate.add_samples(samples)
    end
  end
end
