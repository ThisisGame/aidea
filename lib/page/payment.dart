import 'dart:async';

import 'package:askaide/bloc/payment_bloc.dart';
import 'package:askaide/helper/helper.dart';
import 'package:askaide/helper/logger.dart';
import 'package:askaide/helper/platform.dart';
import 'package:askaide/lang/lang.dart';
import 'package:askaide/page/component/background_container.dart';
import 'package:askaide/page/component/chat/markdown.dart';
import 'package:askaide/page/component/coin.dart';
import 'package:askaide/page/component/enhanced_button.dart';
import 'package:askaide/page/component/loading.dart';
import 'package:askaide/page/dialog.dart';
import 'package:askaide/page/theme/custom_size.dart';
import 'package:askaide/page/theme/custom_theme.dart';
import 'package:askaide/repo/api/payment.dart';
import 'package:askaide/repo/api_server.dart';
import 'package:askaide/repo/settings_repo.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:tobias/tobias.dart';

class PaymentScreen extends StatefulWidget {
  final SettingRepository setting;
  const PaymentScreen({super.key, required this.setting});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Function()? _cancelLoading;

  @override
  void initState() {
    if (PlatformTool.isIOS() || PlatformTool.isMacOS()) {
      final purchaseUpdated = InAppPurchase.instance.purchaseStream;
      _subscription = purchaseUpdated.listen((purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      }, onDone: () {
        _subscription?.cancel();
      }, onError: (error) {
        showErrorMessage(resolveError(context, error));
      });
    } else {
      // 支付宝支付
    }

    // 加载支付产品列表
    context.read<PaymentBloc>().add(PaymentLoadAppleProducts());

    super.initState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // 支付 ID
  String? paymentId;

  ProductDetails? selectedProduct;

  /// 监听支付状态
  void _listenToPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (var purchaseDetails in purchaseDetailsList) {
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          await APIServer().updateApplePay(
            paymentId!,
            productId: purchaseDetails.productID,
            localVerifyData:
                purchaseDetails.verificationData.localVerificationData,
            serverVerifyData:
                purchaseDetails.verificationData.serverVerificationData,
            verifyDataSource: purchaseDetails.verificationData.source,
          );

          break;
        case PurchaseStatus.error:
          APIServer()
              .cancelApplePay(
            paymentId!,
            reason: purchaseDetails.error.toString(),
          )
              .whenComplete(() {
            _closePaymentLoading();
            showErrorMessage(resolveError(context, purchaseDetails.error!));
          });

          break;
        case PurchaseStatus.purchased: // fall through
          if (paymentId != null) {
            APIServer()
                .verifyApplePay(
              paymentId!,
              productId: purchaseDetails.productID,
              purchaseId: purchaseDetails.purchaseID,
              transactionDate: purchaseDetails.transactionDate,
              localVerifyData:
                  purchaseDetails.verificationData.localVerificationData,
              serverVerifyData:
                  purchaseDetails.verificationData.serverVerificationData,
              verifyDataSource: purchaseDetails.verificationData.source,
              status: purchaseDetails.status.toString(),
            )
                .then((status) {
              _closePaymentLoading();
              showSuccessMessage('购买成功');
            }).onError((error, stackTrace) {
              _closePaymentLoading();
              showErrorMessage(resolveError(context, error!));
            });
          }

          break;
        case PurchaseStatus.restored:
          Logger.instance.d('恢复购买');
          _closePaymentLoading();
          showSuccessMessage('恢复成功');
          break;
        case PurchaseStatus.canceled:
          APIServer().cancelApplePay(paymentId!).whenComplete(() {
            _closePaymentLoading();
            showErrorMessage('购买已取消');
          });

          break;
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchaseDetails);
      }
    }
  }

  /// 关闭支付中的 loading
  void _closePaymentLoading() {
    paymentId = null;
    if (_cancelLoading != null) {
      _cancelLoading!();
      _cancelLoading = null;
    }
  }

  /// 开始支付中的 loading
  void _startPaymentLoading() {
    _cancelLoading = BotToast.showCustomLoading(
      toastBuilder: (cancel) {
        return LoadingIndicator(
          message: AppLocale.processingWait.getString(context),
        );
      },
      allowClick: false,
      duration: const Duration(seconds: 120),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>()!;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: CustomSize.toolbarHeight,
        elevation: 0,
        title: Text(
          AppLocale.buyCoins.getString(context),
          style: const TextStyle(
            fontSize: CustomSize.appBarTitleSize,
          ),
        ),
        actions: [
          TextButton(
            style: ButtonStyle(
              overlayColor: MaterialStateProperty.all(Colors.transparent),
            ),
            onPressed: () {
              context.push('/quota-details');
            },
            child: Text(
              AppLocale.paymentHistory.getString(context),
              style: TextStyle(color: customColors.weakLinkColor),
              textScaleFactor: 0.9,
            ),
          ),
          // TextButton(
          //   style: ButtonStyle(
          //     overlayColor: MaterialStateProperty.all(Colors.transparent),
          //   ),
          //   onPressed: () {
          //     _startPaymentLoading();
          //     // 恢复购买
          //     InAppPurchase.instance.restorePurchases().whenComplete(() {
          //       _closePaymentLoading();
          //       showSuccessMessage('恢复完成');
          //     });
          //   },
          //   child: Text(
          //     '恢复购买',
          //     style: TextStyle(color: customColors.weakLinkColor),
          //     textScaleFactor: 0.9,
          //   ),
          // ),
        ],
      ),
      backgroundColor: customColors.backgroundContainerColor,
      body: BackgroundContainer(
        setting: widget.setting,
        enabled: false,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: BlocConsumer<PaymentBloc, PaymentState>(
              listener: (context, state) {
                if (state is PaymentAppleProductsLoaded) {
                  if (state.error != null) {
                    showErrorMessage(resolveError(context, state.error!));
                  } else {
                    if (state.localProducts.isEmpty) {
                      showErrorMessage('暂无可购买的产品');
                    } else {
                      final recommends = state.localProducts
                          .where((e) => e.recommend)
                          .toList();
                      if (recommends.isNotEmpty && !state.loading) {
                        setState(() {
                          selectedProduct = state.products
                              .firstWhere((e) => e.id == recommends.first.id);
                        });
                      }
                    }
                  }
                }
              },
              buildWhen: (previous, current) =>
                  current is PaymentAppleProductsLoaded,
              builder: (context, state) {
                if (state is! PaymentAppleProductsLoaded) {
                  return const Center(child: LoadingIndicator());
                }

                if (state.error != null) {
                  return Center(
                    child: Text(
                      state.error.toString(),
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                return Column(
                  children: [
                    Column(
                      children: [
                        for (var item in state.products)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedProduct = item;
                              });
                            },
                            child: PriceBlock(
                              customColors: customColors,
                              detail: item,
                              selectedProduct: selectedProduct,
                              product: state.localProducts
                                  .firstWhere((e) => e.id == item.id),
                              loading: state.loading,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (selectedProduct != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: Text(
                          state.localProducts
                              .where((e) => e.id == selectedProduct!.id)
                              .first
                              .description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: customColors.weakTextColor,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: EnhancedButton(
                        title:
                            '${AppLocale.toPay.getString(context)}   ${selectedProduct?.price ?? ''}',
                        onPressed: () async {
                          if (state.loading) {
                            showErrorMessage('价格加载中，请稍后');
                            return;
                          }
                          if (selectedProduct == null) {
                            showErrorMessage('请选择购买的产品');
                            return;
                          }

                          _startPaymentLoading();
                          try {
                            if (PlatformTool.isIOS() ||
                                PlatformTool.isMacOS()) {
                              // 创建支付，服务端保存支付信息，创建支付订单
                              paymentId = await APIServer()
                                  .createApplePay(selectedProduct!.id);
                              // 发起 Apple 支付
                              InAppPurchase.instance.buyConsumable(
                                purchaseParam: PurchaseParam(
                                    productDetails: selectedProduct!),
                              );
                            } else {
                              // 支付宝支付
                              final created = await APIServer().createAlipay(
                                selectedProduct!.id,
                              );
                              paymentId = created.paymentId;

                              // 调起支付宝支付
                              final aliPayRes = await aliPay(
                                created.params,
                                evn: AliPayEvn.ONLINE,
                              ).whenComplete(() => _closePaymentLoading());
                              print("=================");
                              print(aliPayRes);
                              print(aliPayRes["resultStatus"]);
                              if (aliPayRes['resultStatus'] == '9000') {
                                await APIServer().alipayClientConfirm(
                                  aliPayRes.map((key, value) =>
                                      MapEntry(key.toString(), value)),
                                );

                                showSuccessMessage('购买成功');
                              } else {
                                switch (aliPayRes['resultStatus']) {
                                  case 8000: // fall through
                                  case 6004:
                                    showErrorMessage('支付处理中，请稍后查看购买历史确认结果');
                                    break;
                                  case 4000:
                                    showErrorMessage('支付失败');
                                    break;
                                  case 5000:
                                    showErrorMessage('重复请求');
                                    break;
                                  case 6001:
                                    showErrorMessage('支付已取消');
                                    break;
                                  case 6002:
                                    showErrorMessage('网络连接出错');
                                    break;
                                  default:
                                    showErrorMessage('支付失败');
                                }
                              }
                              print("-----------------");
                            }
                          } catch (e) {
                            _closePaymentLoading();
                            showErrorMessage(resolveError(context, e));
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (state.note != null)
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '   购买说明：',
                              style: TextStyle(
                                fontSize: 12,
                                color: customColors.paymentItemTitleColor
                                    ?.withOpacity(0.5),
                              ),
                            ),
                            Markdown(
                              data: state.note!,
                              textStyle: TextStyle(
                                color: customColors.paymentItemTitleColor
                                    ?.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class PriceBlock extends StatelessWidget {
  final CustomColors customColors;
  final ProductDetails detail;
  final ProductDetails? selectedProduct;
  final AppleProduct product;
  final bool loading;

  const PriceBlock({
    super.key,
    required this.customColors,
    required this.detail,
    this.selectedProduct,
    required this.product,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>()!;
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          padding: const EdgeInsets.all(20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: customColors.paymentItemBackgroundColor,
            border: Border.all(
              color:
                  (selectedProduct != null && selectedProduct!.id == detail.id)
                      ? customColors.linkColor ?? Colors.green
                      : customColors.paymentItemBackgroundColor!,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Coin(
                    count: product.quota,
                    color: customColors.paymentItemTitleColor,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 11,
                        color: Color.fromARGB(255, 224, 170, 7),
                      ),
                      const SizedBox(width: 1),
                      Text(
                        '${product.expirePolicyText}内有效',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color.fromARGB(255, 224, 170, 7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              loading
                  ? const Text('加载中...')
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (detail.price != product.retailPriceText)
                          Text(
                            product.retailPriceText,
                            style: TextStyle(
                              fontSize: 13,
                              decoration: TextDecoration.lineThrough,
                              color: customColors.paymentItemDescriptionColor
                                  ?.withAlpha(200),
                            ),
                          ),
                        if (detail.price != product.retailPriceText)
                          const SizedBox(width: 10),
                        Text(
                          detail.price,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: customColors.linkColor,
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
        if (product.recommend)
          Positioned(
            right: 11,
            top: 6,
            child: Container(
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 224, 68, 7),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: const Text(
                'Best Deal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          )
      ],
    );
  }
}
